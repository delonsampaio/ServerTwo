import Foundation
import os

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

    private static let log = Logger(subsystem: "com.delonsampaio.ServerTwo", category: "WatchSync")

    /// `nil` when the store could not save (not acknowledged). Every outcome is
    /// logged with the match id and the reason (ids only, never player data):
    /// the Watch deletes its only copy once acknowledged, so "why was this not
    /// imported" must be answerable from the device log afterwards.
    @discardableResult
    public func receive(_ incoming: IncomingSyncedMatch, acknowledger: some PhoneSyncAcknowledging) -> ImportResult? {
        let label = incoming.matchID?.uuidString ?? "unknown"
        if let schema = incoming.schema, schema > SyncedMatchPayload.currentSchemaVersion {
            Self.log.notice("match \(label, privacy: .public): newer schema \(schema, privacy: .public), not stored, NOT acknowledged")
            return .unsupportedNewerSchema
        }
        guard let payload = incoming.payload else {
            // No schema key at all and no readable payload: it may be a shape
            // from a version this app cannot read, so do not acknowledge (that
            // would make the Watch delete its only copy); with a schema this
            // app knows, an unreadable payload is permanently bad.
            if incoming.schema == nil {
                Self.log.notice("match \(label, privacy: .public): no schema key and unreadable payload, NOT acknowledged")
                return .unsupportedNewerSchema
            }
            if let id = incoming.matchID {
                Self.log.error("match \(id.uuidString, privacy: .public): rejected (undecodable payload), acknowledged")
                acknowledger.acknowledge(matchID: id)
            } else {
                Self.log.error("rejected (undecodable payload) with no match id, nothing to acknowledge")
            }
            return .rejected(.undecodablePayload)
        }
        if let labelled = incoming.matchID, labelled != payload.id {
            Self.log.error("match \(label, privacy: .public): rejected (label differs from payload id \(payload.id.uuidString, privacy: .public)), acknowledged")
            acknowledger.acknowledge(matchID: labelled)
            return .rejected(.idMismatch)
        }

        let countBefore = (try? repository.fetchMatchHistory().count) ?? 0
        let result: ImportResult
        do {
            result = try repository.importSyncedMatch(payload)
        } catch {
            Self.log.error("match \(payload.id.uuidString, privacy: .public): storing failed (\(error.localizedDescription, privacy: .public)), NOT acknowledged")
            return nil
        }
        let id = payload.id.uuidString
        switch result {
        case .unsupportedNewerSchema:
            Self.log.notice("match \(id, privacy: .public): payload schema newer than this app, NOT acknowledged")
        case .imported:
            Self.log.info("match \(id, privacy: .public): imported, acknowledged")
            didImport(countBefore)
            acknowledger.acknowledge(matchID: payload.id)
        case .duplicate:
            Self.log.info("match \(id, privacy: .public): duplicate (already here or seen), acknowledged")
            acknowledger.acknowledge(matchID: payload.id)
        case .rejected(let reason):
            Self.log.error("match \(id, privacy: .public): rejected (\(reason.rawValue, privacy: .public)), acknowledged")
            acknowledger.acknowledge(matchID: payload.id)
        }
        return result
    }

}
