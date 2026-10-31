import Foundation
import WatchConnectivity
import os
import PickleballKit

/// The real `WCSession` behind the Watch's sync coordinator: a thin shim, all
/// the decisions live in the tested `WatchSyncCoordinator`.
///
/// `nonisolated` on purpose (the target's default isolation is the main actor):
/// WatchConnectivity calls the delegate on a background queue, and the two
/// callbacks are handed to the main actor as `Sendable` values only (a match
/// id, or nothing), never the session or the raw dictionary.
nonisolated final class WatchSessionTransport: NSObject, WCSessionDelegate, WatchSyncTransport, Sendable {
    private struct Handlers: Sendable {
        let onActivated: @MainActor @Sendable () -> Void
        let onAcknowledged: @MainActor @Sendable (UUID) -> Void
    }

    private let handlers = OSAllocatedUnfairLock<Handlers?>(initialState: nil)
    private let log = Logger(subsystem: "com.delonsampaio.ServerTwo", category: "WatchSync")

    /// One line of WCSession state for the device log (read through Console),
    /// so a transfer that never arrives can be told apart from a session that
    /// never became usable. Cheap and only logged at events, never polled.
    private static func stateSummary() -> String {
        guard WCSession.isSupported() else { return "WCSession unsupported" }
        let session = WCSession.default
        return "activation=\(session.activationState.rawValue) companionInstalled=\(session.isCompanionAppInstalled) "
            + "reachable=\(session.isReachable) outstandingTransfers=\(session.outstandingUserInfoTransfers.count)"
    }

    // MARK: WatchSyncTransport

    var isActivated: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
    }

    func hasOutstandingTransfer(forMatchID id: UUID) -> Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.outstandingUserInfoTransfers.contains {
            SyncedMatchWire.matchID(in: $0.userInfo) == id
        }
    }

    func send(_ message: SyncedMatchMessage) {
        guard isActivated else {
            log.error("watch: match \(message.matchID.uuidString, privacy: .public) NOT queued, session not activated (\(Self.stateSummary(), privacy: .public))")
            return
        }
        // Queued by the system and delivered when the phone is reachable, even
        // after this app is suspended or relaunched.
        WCSession.default.transferUserInfo(message.userInfo)
        log.info("watch: queued match \(message.matchID.uuidString, privacy: .public) (\(Self.stateSummary(), privacy: .public))")
    }

    func start(
        onActivated: @escaping @MainActor @Sendable () -> Void,
        onAcknowledged: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        handlers.withLock { $0 = Handlers(onActivated: onActivated, onAcknowledged: onAcknowledged) }
        guard WCSession.isSupported() else { return }
        // Delegate first, then activate: callbacks that arrive during
        // activation must have somewhere to go.
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error { log.error("watch: WCSession activation failed: \(error.localizedDescription, privacy: .public)") }
        log.info("watch: activation finished (\(Self.stateSummary(), privacy: .public))")
        guard activationState == .activated, let handlers = handlers.withLock({ $0 }) else { return }
        Task { @MainActor in handlers.onActivated() }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Only the phone's acknowledgement matters; extract the id here, on the
        // delegate queue, and hand over just that.
        log.info("watch: received userInfo, ack=\(SyncedMatchWire.acknowledgedMatchID(in: userInfo)?.uuidString ?? "none", privacy: .public) (\(Self.stateSummary(), privacy: .public))")
        guard let id = SyncedMatchWire.acknowledgedMatchID(in: userInfo),
              let handlers = handlers.withLock({ $0 }) else { return }
        Task { @MainActor in handlers.onAcknowledged(id) }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        // A finished transfer is NOT an acknowledgement, so success changes
        // nothing; on failure the id simply stays pending and is queued again
        // at the next launch or Done.
        let id = SyncedMatchWire.matchID(in: userInfoTransfer.userInfo)?.uuidString ?? "unknown"
        if let error {
            log.error("watch: transfer of \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public) (\(Self.stateSummary(), privacy: .public))")
        } else {
            log.info("watch: transfer of \(id, privacy: .public) finished, awaiting the phone's acknowledgement (\(Self.stateSummary(), privacy: .public))")
        }
    }
}
