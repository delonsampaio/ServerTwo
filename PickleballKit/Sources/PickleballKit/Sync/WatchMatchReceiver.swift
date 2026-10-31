import Foundation

/// How the phone tells the Watch it has dealt with a match.
public protocol PhoneSyncAcknowledging: Sendable {
    func acknowledge(matchID: UUID)
}

/// The phone side of sync (B1): turns one received transfer into an import and
/// an acknowledgement, by this table:
///
/// - newer schema than this app knows: nothing is stored, NO ack, NO seen id
///   (the Watch keeps it queued until the phone app is updated)
/// - imported / duplicate: acknowledge
/// - rejected (undecodable or invalid): acknowledge anyway, a permanently bad
///   record must not be resent forever (nothing to ack if no id survived)
/// - the store failed to save: NO ack (transient, the Watch resends)
@MainActor
public final class WatchMatchReceiver {
    private let repository: MatchRepository
    private let didImport: @MainActor (_ historyCountBeforeImport: Int) -> Void

    /// `didImport` runs once per `.imported` match (never for duplicates or
    /// rejects), with the history size read BEFORE the insert, so the app can
    /// feed its demo counter exactly as for a match played on the phone.
    public init(
        repository: MatchRepository,
        didImport: @escaping @MainActor (_ historyCountBeforeImport: Int) -> Void
    ) {
        self.repository = repository
        self.didImport = didImport
    }

    /// `nil` when the store could not save (not acknowledged).
    @discardableResult
    public func receive(_ incoming: IncomingSyncedMatch, acknowledger: some PhoneSyncAcknowledging) -> ImportResult? {
        if let schema = incoming.schema, schema > SyncedMatchPayload.currentSchemaVersion {
            return .unsupportedNewerSchema
        }
        guard let payload = incoming.payload else {
            acknowledgeIfPossible(incoming.matchID, with: acknowledger)
            return .rejected(.undecodablePayload)
        }
        if let labelled = incoming.matchID, labelled != payload.id {
            acknowledger.acknowledge(matchID: labelled)
            return .rejected(.idMismatch)
        }

        let countBefore = (try? repository.fetchMatchHistory().count) ?? 0
        let result: ImportResult
        do {
            result = try repository.importSyncedMatch(payload)
        } catch {
            return nil
        }
        switch result {
        case .unsupportedNewerSchema:
            break
        case .imported:
            didImport(countBefore)
            acknowledger.acknowledge(matchID: payload.id)
        case .duplicate, .rejected:
            acknowledger.acknowledge(matchID: payload.id)
        }
        return result
    }

    private func acknowledgeIfPossible(_ id: UUID?, with acknowledger: some PhoneSyncAcknowledging) {
        if let id { acknowledger.acknowledge(matchID: id) }
    }
}
