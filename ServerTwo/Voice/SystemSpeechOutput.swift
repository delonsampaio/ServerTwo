import Foundation

/// Speaks announcements and owns the audio-session lifecycle.
///
/// Two races this exists to avoid (see the design spec):
/// - `stopSpeaking(.immediate)` then a new `speak` means the cancelled
///   utterance's `didCancel` can arrive AFTER the new utterance started. Every
///   callback is therefore checked against the current utterance's id and
///   ignored when it is stale.
/// - Deactivating the session after every utterance makes background music
///   pump up and down between rapid calls and tears down a warm Bluetooth
///   route. Deactivation is debounced by a quiet window and cancelled by the
///   next `speak`.
final class SystemSpeechOutput: SpeechOutput {
    private let synthesizer: SpeechSynthesizing
    private let session: AudioSessionControlling
    private let quietWindow: Duration
    private let scheduler: DelayedActionScheduler

    private var currentID: UUID?
    private var sessionActive = false
    private var cancelPendingDeactivation: (() -> Void)?
    private var deactivationRetried = false

    /// Lead-in when speech starts from an inactive session, so a waking
    /// Bluetooth route does not swallow the first number.
    private let coldStartDelay: TimeInterval = 0.15

    init(
        synthesizer: SpeechSynthesizing,
        session: AudioSessionControlling,
        quietWindow: Duration = .seconds(1.2),
        scheduler: @escaping DelayedActionScheduler = SystemSpeechOutput.taskScheduler
    ) {
        self.synthesizer = synthesizer
        self.session = session
        self.quietWindow = quietWindow
        self.scheduler = scheduler
        synthesizer.onUtteranceEnded = { [weak self] id in
            self?.utteranceEnded(id)
        }
    }

    static func live() -> SystemSpeechOutput {
        SystemSpeechOutput(
            synthesizer: AVSpeechSynthesizerAdapter(),
            session: AVAudioSessionController()
        )
    }

    static let taskScheduler: DelayedActionScheduler = { delay, action in
        let task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { action() }
        }
        return { task.cancel() }
    }

    func speak(_ text: String) {
        deactivationRetried = false
        cancelPendingDeactivation?()
        cancelPendingDeactivation = nil
        if currentID != nil { synthesizer.stop() }

        let preDelay: TimeInterval = sessionActive ? 0 : coldStartDelay
        if !sessionActive {
            session.activate()
            sessionActive = true
        }
        let id = UUID()
        currentID = id
        synthesizer.speak(text, id: id, preDelay: preDelay)
    }

    func stop() {
        // Nothing spoken since the session was last released: leave the audio
        // session alone (scene-phase changes call this on every backgrounding).
        guard sessionActive else { return }
        synthesizer.stop()
        currentID = nil
        scheduleDeactivation()
    }

    private func utteranceEnded(_ id: UUID) {
        guard id == currentID else { return }   // stale callback
        currentID = nil
        scheduleDeactivation()
    }

    private func scheduleDeactivation() {
        cancelPendingDeactivation?()
        cancelPendingDeactivation = scheduler(quietWindow) { [weak self] in
            guard let self else { return }
            if !self.session.deactivate(), !self.deactivationRetried {
                // The system refused: stay active and try once more.
                self.deactivationRetried = true
                self.scheduleDeactivation()
                return
            }
            // Released, or the retry failed too: stop tracking it as active.
            self.sessionActive = false
            self.deactivationRetried = false
            self.cancelPendingDeactivation = nil
        }
    }
}
