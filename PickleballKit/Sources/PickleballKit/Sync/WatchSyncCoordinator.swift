import Foundation

/// The slice of `WCSession` the Watch's sync logic needs, so the logic can be
/// unit tested with a fake and the real adapter stays a thin shim in the Watch
/// target. Main-actor isolated: the adapter hops there before calling back.
@MainActor
public protocol WatchSyncTransport: AnyObject {
    /// False until `WCSession` finished activating (a transfer before that is lost).
    var isActivated: Bool { get }
    /// Whether a transfer for this match is already queued with the system
    /// (`outstandingUserInfoTransfers`), so it is not queued a second time.
    func hasOutstandingTransfer(forMatchID id: UUID) -> Bool
    func send(_ message: SyncedMatchMessage)
    /// Activates the session and registers the callbacks: activation finished,
    /// and an acknowledgement from the phone.
    func start(
        onActivated: @escaping @MainActor @Sendable () -> Void,
        onAcknowledged: @escaping @MainActor @Sendable (UUID) -> Void
    )
}

/// The Watch side of sync (B1): queue finished matches to the iPhone, and
/// forget them only when the phone says it has them.
///
/// Sync runs ONLY when the user taps Done on the match-over screen and when
/// the session activates at launch; never on a reachability change, and never
/// for the match still on the match-over screen (it can still be undone, and a
/// match sent and then undone would exist twice on the phone). The transfer
/// finishing is not an acknowledgement, only the phone's message is.
@MainActor
public final class WatchSyncCoordinator {
    private let repository: MatchRepository
    private let pendingSync: PendingSyncStore
    private let transport: any WatchSyncTransport
    private let session: StandaloneMatchSession
    /// Test seam: how a record is deleted after an acknowledgement.
    var deleteRecord: (MatchRecord) throws -> Void

    public init(
        repository: MatchRepository,
        pendingSync: PendingSyncStore,
        transport: any WatchSyncTransport,
        session: StandaloneMatchSession
    ) {
        self.repository = repository
        self.pendingSync = pendingSync
        self.transport = transport
        self.session = session
        self.deleteRecord = { try repository.deleteMatch($0) }
    }

    /// Wires the Done trigger and starts the transport (whose activation then
    /// triggers the launch sync). Call once, at app launch.
    public func start() {
        session.onFinishedMatchDismissed = { [weak self] in self?.syncPending() }
        transport.start(
            onActivated: { [weak self] in self?.syncPending() },
            onAcknowledged: { [weak self] id in self?.handleAcknowledgement(matchID: id) }
        )
    }

    /// Queues every pending match that is not held back, not already queued
    /// with the system, and still has a record.
    public func syncPending() {
        guard transport.isActivated else { return }
        let heldBack = session.heldBackMatchIDs
        for id in pendingSync.pendingMatchIDs where !heldBack.contains(id) {
            let record: MatchRecord?
            do {
                record = try repository.fetchMatchRecord(id: id)
            } catch {
                // The store is unreadable right now: keep the id for next time.
                continue
            }
            guard let record else {
                // The match is gone (store fell back to memory, or a crash
                // between marking and saving): nothing to send, nothing to wait for.
                pendingSync.confirmSynced(id)
                continue
            }
            guard !transport.hasOutstandingTransfer(forMatchID: id) else { continue }
            guard let data = try? SyncedMatchPayload(record: record).encoded() else { continue }
            transport.send(SyncedMatchMessage(matchID: id, payload: data))
        }
    }

    /// The phone has the match: stop tracking it and delete the local copy (the
    /// Watch has no history screen). The record goes first and the id only
    /// after, so a failed delete leaves the id pending and the next ack retries.
    public func handleAcknowledgement(matchID id: UUID) {
        // A match still on the match-over screen was never sent, so an ack for
        // it can only be stale; leave it queued and untouched until Done.
        guard !session.heldBackMatchIDs.contains(id), pendingSync.isPending(id) else { return }
        do {
            if let record = try repository.fetchMatchRecord(id: id) {
                try deleteRecord(record)
            }
        } catch {
            return
        }
        pendingSync.confirmSynced(id)
    }
}
