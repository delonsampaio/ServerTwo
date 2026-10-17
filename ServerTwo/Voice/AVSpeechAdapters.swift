import AVFoundation

/// Thin `AVSpeechSynthesizer` wrapper. No logic beyond mapping utterances to
/// the ids `SystemSpeechOutput` tracks; verified on a device, not in unit
/// tests. The project builds with MainActor default isolation, and
/// `AVSpeechSynthesizerDelegate` is not main-actor isolated, so the delegate
/// methods are `nonisolated` and hop back carrying only the utterance's
/// `ObjectIdentifier`.
final class AVSpeechSynthesizerAdapter: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    var onUtteranceEnded: (@MainActor (UUID) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// The utterance is held strongly alongside its id so its address (the
    /// `ObjectIdentifier`) cannot be reused by a new utterance until the entry
    /// is removed; otherwise a stale queued callback could remove a live entry.
    private var ids: [ObjectIdentifier: (utterance: AVSpeechUtterance, id: UUID)] = [:]

    /// Every announcement sentence is English, so the voice must be English
    /// even on a device set to another language.
    static func voiceLanguage(deviceLanguage: String) -> String {
        deviceLanguage.lowercased().hasPrefix("en") ? deviceLanguage : "en-US"
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, id: UUID, preDelay: TimeInterval) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(
            language: Self.voiceLanguage(deviceLanguage: AVSpeechSynthesisVoice.currentLanguageCode())
        )
        utterance.preUtteranceDelay = preDelay
        ids[ObjectIdentifier(utterance)] = (utterance, id)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(key) }
    }

    private func ended(_ key: ObjectIdentifier) {
        guard let id = ids.removeValue(forKey: key)?.id else { return }
        onUtteranceEnded?(id)
    }
}

/// `.playback` plays through the silent switch and to Bluetooth; `.voicePrompt`
/// is the mode for brief spoken prompts; ducking lowers music and
/// `.interruptSpokenAudioAndMixWithOthers` pauses podcasts/audiobooks for the
/// call instead of talking over them. The category is set once, lazily.
final class AVAudioSessionController: AudioSessionControlling {
    private var configured = false

    func activate() {
        let session = AVAudioSession.sharedInstance()
        if !configured {
            do {
                try session.setCategory(
                    .playback, mode: .voicePrompt,
                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
                )
                configured = true
            } catch {
                // Leave `configured` false so the next activation retries.
            }
        }
        try? session.setActive(true)
    }

    /// Returns false when the system refused, so the caller can retry.
    func deactivate() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return true
        } catch {
            return false
        }
    }
}
