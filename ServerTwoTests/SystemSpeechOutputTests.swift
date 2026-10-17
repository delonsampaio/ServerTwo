import XCTest
@testable import ServerTwo

@MainActor
final class SystemSpeechOutputTests: XCTestCase {
    private final class FakeSynthesizer: SpeechSynthesizing {
        var onUtteranceEnded: (@MainActor (UUID) -> Void)?
        struct Spoken { let text: String; let id: UUID; let preDelay: TimeInterval }
        var spoken: [Spoken] = []
        var stopCount = 0
        func speak(_ text: String, id: UUID, preDelay: TimeInterval) {
            spoken.append(Spoken(text: text, id: id, preDelay: preDelay))
        }
        func stop() { stopCount += 1 }
    }

    private final class FakeSession: AudioSessionControlling {
        var activateCount = 0
        var deactivateCount = 0
        func activate() { activateCount += 1 }
        func deactivate() { deactivateCount += 1 }
    }

    /// Captures scheduled actions; `fire()` runs every one that was not cancelled.
    @MainActor private final class FakeScheduler {
        private struct Entry { var action: @MainActor () -> Void; var done: Bool }
        private var entries: [Entry] = []
        /// Actions scheduled and neither cancelled nor run yet.
        var scheduledCount: Int { entries.filter { !$0.done }.count }
        func schedule(_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> () -> Void {
            entries.append(Entry(action: action, done: false))
            let index = entries.count - 1
            return { [unowned self] in self.entries[index].done = true }
        }
        func fire() {
            for index in entries.indices where !entries[index].done {
                entries[index].done = true
                entries[index].action()
            }
        }
    }

    private func makeOutput() -> (SystemSpeechOutput, FakeSynthesizer, FakeSession, FakeScheduler) {
        let synth = FakeSynthesizer()
        let session = FakeSession()
        let scheduler = FakeScheduler()
        let output = SystemSpeechOutput(
            synthesizer: synth, session: session, quietWindow: .seconds(1.2),
            scheduler: { delay, action in scheduler.schedule(delay, action) }
        )
        return (output, synth, session, scheduler)
    }

    func testTheFirstSpeakActivatesTheSessionWithALeadInAndALaterOneDoesNot() {
        let (output, synth, session, _) = makeOutput()
        output.speak("4, 2, 1.")
        XCTAssertEqual(session.activateCount, 1)
        XCTAssertEqual(synth.spoken[0].text, "4, 2, 1.")
        XCTAssertEqual(synth.spoken[0].preDelay, 0.15, accuracy: 0.0001)

        output.speak("5, 2, 1.")
        XCTAssertEqual(session.activateCount, 1, "the session is already warm")
        XCTAssertEqual(synth.spoken[1].preDelay, 0, accuracy: 0.0001)
    }

    func testSpeakingWhileAnotherUtteranceIsInFlightStopsItFirst() {
        let (output, synth, _, _) = makeOutput()
        output.speak("4, 2, 1.")
        XCTAssertEqual(synth.stopCount, 0)
        output.speak("5, 2, 1.")
        XCTAssertEqual(synth.stopCount, 1)
        XCTAssertEqual(synth.spoken.count, 2)
    }

    func testALateCallbackForACancelledUtteranceIsIgnored() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        let first = synth.spoken[0].id
        output.speak("5, 2, 1.")

        // The cancelled first utterance reports in AFTER the second started.
        synth.onUtteranceEnded?(first)
        XCTAssertEqual(scheduler.scheduledCount, 0, "a stale callback must not schedule deactivation")
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 0)
    }

    func testFinishingTheCurrentUtteranceDeactivatesOnlyAfterTheQuietWindow() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        synth.onUtteranceEnded?(synth.spoken[0].id)
        XCTAssertEqual(session.deactivateCount, 0, "not before the quiet window elapses")

        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 1)

        // The next call starts from an inactive session again.
        output.speak("5, 2, 1.")
        XCTAssertEqual(session.activateCount, 2)
        XCTAssertEqual(synth.spoken[1].preDelay, 0.15, accuracy: 0.0001)
    }

    func testSpeakingDuringTheQuietWindowCancelsTheDeactivation() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        synth.onUtteranceEnded?(synth.spoken[0].id)   // schedules deactivation
        output.speak("5, 2, 1.")                      // cancels it
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 0)
        XCTAssertEqual(session.activateCount, 1)
    }

    func testStopWhenNothingIsActiveDoesNothing() {
        let (output, synth, session, scheduler) = makeOutput()
        output.stop()
        XCTAssertEqual(synth.stopCount, 0)
        XCTAssertEqual(scheduler.scheduledCount, 0)
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 0)
        XCTAssertEqual(session.activateCount, 0)
    }

    func testStopCutsSpeechAndSchedulesDeactivation() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        output.stop()
        XCTAssertEqual(synth.stopCount, 1)
        // The cancel callback for the stopped utterance is stale (no current id).
        synth.onUtteranceEnded?(synth.spoken[0].id)
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 1)
    }
}
