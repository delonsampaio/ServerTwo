import Observation
import UIKit

/// The single place the "should we speak at all" checks live. Owned by
/// `MyApp`, injected through the environment.
@Observable
final class VoiceAnnouncer {
    @ObservationIgnored private let output: SpeechOutput
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private let isVoiceOverRunning: @MainActor () -> Bool

    init(
        output: SpeechOutput,
        isEnabled: @escaping @MainActor () -> Bool,
        isVoiceOverRunning: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }
    ) {
        self.output = output
        self.isEnabled = isEnabled
        self.isVoiceOverRunning = isVoiceOverRunning
    }

    /// `lines` are the planner's sentences. They are joined into ONE utterance
    /// so a single announcement never has more than one utterance in flight.
    /// VoiceOver already reads the score zones' label changes, so the
    /// announcer stays silent when it is running.
    func announce(_ lines: [String]) {
        guard !lines.isEmpty, isEnabled(), !isVoiceOverRunning() else { return }
        output.speak(lines.joined(separator: " "))
    }

    func stop() {
        output.stop()
    }
}
