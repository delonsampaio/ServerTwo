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
nonisolated final class PhoneWatchSync: NSObject, WCSessionDelegate, PhoneSyncAcknowledging, PhoneStatePushing, Sendable {
    private let handler: @MainActor @Sendable (IncomingSyncedMatch, any PhoneSyncAcknowledging) -> Void
    /// Runs on the main actor each time the session finishes activating, which
    /// is when the phone (re)publishes its Pro flag and demo count.
    private let onActivated: @MainActor @Sendable () -> Void
    private let log = Logger(subsystem: "com.delonsampaio.ServerTwo", category: "WatchSync")

    /// One line of WCSession state for the device log (Console): activation,
    /// pairing, whether the Watch app is installed, reachability and queued
    /// transfers. Logged at events only, never polled.
    private static func stateSummary() -> String {
        guard WCSession.isSupported() else { return "WCSession unsupported" }
        let session = WCSession.default
        return "activation=\(session.activationState.rawValue) paired=\(session.isPaired) "
            + "watchAppInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable) "
            + "outstandingTransfers=\(session.outstandingUserInfoTransfers.count)"
    }

    init(
        handler: @escaping @MainActor @Sendable (IncomingSyncedMatch, any PhoneSyncAcknowledging) -> Void,
        onActivated: @escaping @MainActor @Sendable () -> Void
    ) {
        self.handler = handler
        self.onActivated = onActivated
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
              WCSession.default.isPaired else {
            // The Watch will resend and get another chance; say so in the log.
            log.error("phone: acknowledgement for \(matchID.uuidString, privacy: .public) NOT sent (\(Self.stateSummary(), privacy: .public))")
            return
        }
        // Queued by the system; if it is lost the Watch resends and the phone
        // simply answers "duplicate" and acknowledges again.
        WCSession.default.transferUserInfo(SyncedMatchWire.acknowledgementUserInfo(for: matchID))
        log.info("phone: acknowledgement for \(matchID.uuidString, privacy: .public) queued (\(Self.stateSummary(), privacy: .public))")
    }

    // MARK: PhoneStatePushing

    /// The phone's Pro flag and demo count for the Watch's free-demo gate. Only
    /// the latest value matters, which is what an application context is for.
    /// Errors are ignored (the next trigger pushes again) but logged.
    func push(_ context: PhoneStateContext) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired else {
            log.notice("phone: state push skipped (\(Self.stateSummary(), privacy: .public))")
            return
        }
        do {
            try WCSession.default.updateApplicationContext(context.applicationContext)
            log.info("phone: pushed state pro=\(context.proUnlocked, privacy: .public) count=\(context.completedMatchCount, privacy: .public)")
        } catch {
            log.error("phone: state push failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error { log.error("phone: WCSession activation failed: \(error.localizedDescription, privacy: .public)") }
        log.info("phone: activation finished (\(Self.stateSummary(), privacy: .public))")
        guard activationState == .activated else { return }
        let onActivated = onActivated
        Task { @MainActor in onActivated() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS after the user switches to another paired Watch;
        // without a fresh activation no further transfer would ever arrive.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        log.info("phone: received userInfo (\(Self.stateSummary(), privacy: .public))")
        guard let incoming = IncomingSyncedMatch(userInfo: userInfo) else {
            log.notice("phone: userInfo ignored, not a match transfer")
            return
        }
        let handler = handler
        let acknowledger: any PhoneSyncAcknowledging = self
        Task { @MainActor in handler(incoming, acknowledger) }
    }
}
#endif
