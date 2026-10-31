#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity
import os
import PickleballKit

/// The phone's end of Watch sync: owns the `WCSession`, hands every received
/// match to the (tested, main-actor) `WatchMatchReceiver` and sends the
/// acknowledgement it decides on.
///
/// `nonisolated` on purpose (the target's default isolation is the main actor):
/// WatchConnectivity calls the delegate on a background queue. It is created
/// and activated synchronously in `MyApp.init`, before any view, because a
/// transfer delivered while the app was not running is handed over right after
/// activation and would be lost if nothing were listening yet. A transfer is
/// decoded here, on the delegate queue, into `Sendable` values; only those hop
/// to the main actor.
nonisolated final class PhoneWatchSync: NSObject, WCSessionDelegate, PhoneSyncAcknowledging, Sendable {
    private let handler: @MainActor @Sendable (IncomingSyncedMatch, any PhoneSyncAcknowledging) -> Void
    private let log = Logger(subsystem: "com.delonsampaio.ServerTwo", category: "watch-sync")

    init(handler: @escaping @MainActor @Sendable (IncomingSyncedMatch, any PhoneSyncAcknowledging) -> Void) {
        self.handler = handler
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        // Delegate first: see the type's comment.
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: PhoneSyncAcknowledging

    func acknowledge(matchID: UUID) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired else { return }
        // Queued by the system; if it is lost the Watch resends and the phone
        // simply answers "duplicate" and acknowledges again.
        WCSession.default.transferUserInfo(SyncedMatchWire.acknowledgementUserInfo(for: matchID))
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error { log.error("WCSession activation failed: \(error.localizedDescription)") }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS after the user switches to another paired Watch;
        // without a fresh activation no further transfer would ever arrive.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let incoming = IncomingSyncedMatch(userInfo: userInfo) else { return }
        let handler = handler
        let acknowledger: any PhoneSyncAcknowledging = self
        Task { @MainActor in handler(incoming, acknowledger) }
    }
}
#endif
