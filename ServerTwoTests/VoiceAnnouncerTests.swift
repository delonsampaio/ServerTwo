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

    @MainActor private final class PostedBox {
        var posted: [String] = []
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

    func testWithVoiceOverRunningTheLinesAreAnnouncedNotSpoken() {
        let output = RecordingOutput()
        let box = PostedBox()
        let announcer = VoiceAnnouncer(
            output: output, isEnabled: { true }, isVoiceOverRunning: { true },
            postAnnouncement: { box.posted.append($0) }
        )
        announcer.announce(["Side out.", "Fred serving.", "2, 4, 1."])
        XCTAssertTrue(output.spoken.isEmpty, "The synthesizer never speaks under VoiceOver")
        XCTAssertEqual(box.posted, ["Side out. Fred serving. 2, 4, 1."])
    }

    func testWithVoiceOverRunningAndTheToggleOffTheLinesAreStillAnnounced() {
        let output = RecordingOutput()
        let box = PostedBox()
        let announcer = VoiceAnnouncer(
            output: output, isEnabled: { false }, isVoiceOverRunning: { true },
            postAnnouncement: { box.posted.append($0) }
        )
        announcer.announce(["4, 2, 1."])
        XCTAssertTrue(output.spoken.isEmpty)
        XCTAssertEqual(box.posted, ["4, 2, 1."])
    }

    func testWithVoiceOverOffAndTheToggleOffNothingIsSpokenOrPosted() {
        let output = RecordingOutput()
        let box = PostedBox()
        let announcer = VoiceAnnouncer(
            output: output, isEnabled: { false }, isVoiceOverRunning: { false },
            postAnnouncement: { box.posted.append($0) }
        )
        announcer.announce(["4, 2, 1."])
        XCTAssertTrue(output.spoken.isEmpty)
        XCTAssertTrue(box.posted.isEmpty)
    }

    func testEmptyLinesPostNothingUnderVoiceOver() {
        let output = RecordingOutput()
        let box = PostedBox()
        let announcer = VoiceAnnouncer(
            output: output, isEnabled: { true }, isVoiceOverRunning: { true },
            postAnnouncement: { box.posted.append($0) }
        )
        announcer.announce([])
        XCTAssertTrue(output.spoken.isEmpty)
        XCTAssertTrue(box.posted.isEmpty)
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
