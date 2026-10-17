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

    /// The session is switched on and off asynchronously (the synchronous
    /// `setActive` blocks the main thread), so there are in-between states.
    private enum SessionState { case inactive, activating, active, deactivating }

    private var currentID: UUID?
    private var state: SessionState = .inactive
    private var cancelPendingDeactivation: (() -> Void)?
    private var deactivationRetried = false
    /// Latest-wins across the async gap: text waiting for activation to
    /// complete. Each `speak` overwrites it, so only the last is ever spoken.
    private var pendingText: String?
    /// A `speak` arrived while deactivating; reactivate once that completes.
    private var reactivateAfterDeactivation = false

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
        pendingText = text

        switch state {
        case .active:
            speakPending(preDelay: 0)
        case .inactive:
            startActivation()
        case .activating:
            break   // the completion speaks whatever `pendingText` is by then
        case .deactivating:
            reactivateAfterDeactivation = true
        }
    }

    func stop() {
        pendingText = nil
        switch state {
        case .inactive, .deactivating, .activating:
            // Nothing is playing. Idle: leave the audio session alone
            // (scene-phase changes call this on every backgrounding). While
            // activating, the completion finds no text and schedules the
            // deactivation itself.
            return
        case .active:
            synthesizer.stop()
            currentID = nil
            scheduleDeactivation()
        }
    }

    private func startActivation() {
        state = .activating
        session.activate { [weak self] ok in
            self?.activationCompleted(ok)
        }
    }

    private func activationCompleted(_ ok: Bool) {
        // Ignore a duplicate or late completion for an activation that is
        // no longer the one in flight.
        guard state == .activating else { return }
        // Active even when activation failed: speech is still attempted.
        state = .active
        if pendingText != nil {
            speakPending(preDelay: coldStartDelay)   // this was a cold start
        } else {
            scheduleDeactivation()   // `stop()` cancelled it meanwhile
        }
    }

    private func speakPending(preDelay: TimeInterval) {
        guard let text = pendingText else { return }
        pendingText = nil
        let id = UUID()
        currentID = id
        synthesizer.speak(text, id: id, preDelay: preDelay)
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
            self.cancelPendingDeactivation = nil
            guard self.state == .active else { return }
            self.state = .deactivating
            self.session.deactivate { [weak self] ok in
                self?.deactivationCompleted(ok)
            }
        }
    }

    private func deactivationCompleted(_ ok: Bool) {
        guard state == .deactivating else { return }
        if reactivateAfterDeactivation {
            // A `speak` arrived meanwhile: bring the session straight back.
            reactivateAfterDeactivation = false
            state = .inactive
            startActivation()
        } else if ok {
            state = .inactive
            deactivationRetried = false
        } else if !deactivationRetried {
            // The system refused: stay active and try once more.
            state = .active
            deactivationRetried = true
            scheduleDeactivation()
        } else {
            // The retry failed too: stop tracking it as active.
            state = .inactive
            deactivationRetried = false
        }
    }
}
