import Observation
import UIKit

/// The single place the "should we speak or announce at all" checks live.
/// Owned by `MyApp`, injected through the environment.
@Observable
final class VoiceAnnouncer {
    @ObservationIgnored private let output: SpeechOutput
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private let isVoiceOverRunning: @MainActor () -> Bool
    @ObservationIgnored private let postAnnouncement: @MainActor (String) -> Void

    init(
        output: SpeechOutput,
        isEnabled: @escaping @MainActor () -> Bool,
        isVoiceOverRunning: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning },
        postAnnouncement: @escaping @MainActor (String) -> Void = { VoiceOverAnnouncement.post($0) }
    ) {
        self.output = output
        self.isEnabled = isEnabled
        self.isVoiceOverRunning = isVoiceOverRunning
        self.postAnnouncement = postAnnouncement
    }

    /// `lines` are the planner's sentences. They are joined into ONE utterance
    /// so a single announcement never has more than one utterance in flight.
    /// With VoiceOver running, the same text is posted as an accessibility
    /// announcement instead of being spoken: it is the VoiceOver user's only
    /// feedback for a score change, so it is sent regardless of the Voice
    /// Announcer toggle, which (default off) governs only the spoken
    /// synthesizer voice. The synthesizer never speaks under VoiceOver.
    func announce(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: " ")
        if isVoiceOverRunning() {
            postAnnouncement(text)
        } else if isEnabled() {
            output.speak(text)
        }
    }

    func stop() {
        output.stop()
    }
}
