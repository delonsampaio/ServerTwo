import WatchKit
import PickleballKit

/// One place that maps what a tap did to a haptic, so the feel can be tuned
/// after device testing without touching the views.
enum WatchHaptics {
    static func play(for outcome: StandaloneMatchSession.PointOutcome) {
        let device = WKInterfaceDevice.current()
        switch outcome {
        case .ignored:
            break
        case .point:
            device.play(.click)
        case .secondServer, .sideOut:
            // Stronger than a point: no number changed, so the wrist is the
            // only confirmation that the serve moved.
            device.play(.notification)
        case .gameOver, .matchOver:
            device.play(.success)
        }
    }

    static func playUndo() {
        WKInterfaceDevice.current().play(.click)
    }

    /// Done on the match-over screen: a plain tap confirmation, not an undo.
    static func playDone() {
        WKInterfaceDevice.current().play(.click)
    }

    static func playNotice() {
        WKInterfaceDevice.current().play(.notification)
    }
}
