import XCTest
@testable import ServerTwo

@MainActor
final class VoiceAnnouncerTests: XCTestCase {
    private final class RecordingOutput: SpeechOutput {
        var spoken: [String] = []
        var stopCount = 0
        func speak(_ text: String) { spoken.append(text) }
        func stop() { stopCount += 1 }
    }

    @MainActor private final class Flag {
        var value: Bool
        init(_ value: Bool) { self.value = value }
    }

    func testLinesAreJoinedIntoOneUtterance() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { true }, isVoiceOverRunning: { false })
        announcer.announce(["6, 3, 2.", "Switch sides."])
        XCTAssertEqual(output.spoken, ["6, 3, 2. Switch sides."])
    }

    func testNoLinesSpeaksNothing() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { true }, isVoiceOverRunning: { false })
        announcer.announce([])
        XCTAssertTrue(output.spoken.isEmpty)
    }

    func testADisabledToggleSpeaksNothing() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { false }, isVoiceOverRunning: { false })
        announcer.announce(["4, 2, 1."])
        XCTAssertTrue(output.spoken.isEmpty)
    }

    func testVoiceOverRunningSpeaksNothing() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { true }, isVoiceOverRunning: { true })
        announcer.announce(["4, 2, 1."])
        XCTAssertTrue(output.spoken.isEmpty)
    }

    func testTheToggleIsReadAtAnnounceTimeNotCapturedOnce() {
        let output = RecordingOutput()
        let enabled = Flag(true)
        let announcer = VoiceAnnouncer(output: output, isEnabled: { enabled.value }, isVoiceOverRunning: { false })
        announcer.announce(["4, 2, 1."])
        enabled.value = false
        announcer.announce(["5, 2, 1."])
        XCTAssertEqual(output.spoken, ["4, 2, 1."])
    }

    func testStopForwardsToTheOutput() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { true }, isVoiceOverRunning: { false })
        announcer.stop()
        XCTAssertEqual(output.stopCount, 1)
    }
}
