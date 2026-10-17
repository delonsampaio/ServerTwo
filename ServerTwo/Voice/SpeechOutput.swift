import Foundation

/// Where an announcement's text goes. Real speech, or nothing (UI tests).
protocol SpeechOutput {
    func speak(_ text: String)
    func stop()
}

/// Used under UI tests so they never touch the audio session.
struct NullSpeechOutput: SpeechOutput {
    func speak(_ text: String) {}
    func stop() {}
}

/// Wraps `AVSpeechSynthesizer` so `SystemSpeechOutput`'s logic can be tested
/// with a fake. Reports the end of an utterance (finished OR cancelled) by id.
protocol SpeechSynthesizing: AnyObject {
    var onUtteranceEnded: (@MainActor (UUID) -> Void)? { get set }
    func speak(_ text: String, id: UUID, preDelay: TimeInterval)
    func stop()
}

/// Wraps `AVAudioSession` activation so `SystemSpeechOutput`'s logic can be
/// tested with a fake. Both calls are asynchronous: the synchronous
/// `setActive` blocks the main thread (the system logs a warning and a
/// Bluetooth route can stall the UI), so the result arrives in a completion.
protocol AudioSessionControlling {
    /// Asynchronously activates; the completion reports whether it succeeded.
    func activate(completion: @escaping @MainActor (Bool) -> Void)
    /// Asynchronously deactivates (with notify-others); the completion reports success.
    func deactivate(completion: @escaping @MainActor (Bool) -> Void)
}

/// Schedules `action` after a delay and returns a closure that cancels it.
typealias DelayedActionScheduler = @MainActor (Duration, @escaping @MainActor () -> Void) -> () -> Void
