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

    /// Records each asynchronous call and keeps its completion closure so a
    /// test decides when (and with what result) the system "answers". A
    /// closure can be invoked more than once on purpose, to model a
    /// misbehaving system.
    @MainActor private final class FakeSession: AudioSessionControlling {
        private(set) var activations: [@MainActor (Bool) -> Void] = []
        private(set) var deactivations: [@MainActor (Bool) -> Void] = []
        var activateCount: Int { activations.count }
        var deactivateCount: Int { deactivations.count }
        func activate(completion: @escaping @MainActor (Bool) -> Void) { activations.append(completion) }
        func deactivate(completion: @escaping @MainActor (Bool) -> Void) { deactivations.append(completion) }
        /// Completes the latest (default) or the given activation call.
        func completeActivation(_ ok: Bool, at index: Int? = nil) {
            activations[index ?? activations.count - 1](ok)
        }
        func completeDeactivation(_ ok: Bool, at index: Int? = nil) {
            deactivations[index ?? deactivations.count - 1](ok)
        }
    }

    /// Captures scheduled actions; `fire()` runs every one that was not cancelled.
    @MainActor private final class FakeScheduler {
        private struct Entry { var action: @MainActor () -> Void; var done: Bool }
        private var entries: [Entry] = []
        private(set) var delays: [Duration] = []
        /// Actions scheduled and neither cancelled nor run yet.
        var scheduledCount: Int { entries.filter { !$0.done }.count }
        func schedule(_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> () -> Void {
            delays.append(delay)
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

    /// Cold speak, then the system finishes activating: the session is warm.
    private func speakCold(
        _ text: String, _ output: SystemSpeechOutput, _ session: FakeSession
    ) {
        output.speak(text)
        session.completeActivation(true)
    }

    func testAColdSpeakWaitsForActivationThenSpeaksWithALeadIn() {
        let (output, synth, session, _) = makeOutput()
        output.speak("4, 2, 1.")
        XCTAssertEqual(session.activateCount, 1)
        XCTAssertTrue(synth.spoken.isEmpty, "nothing is spoken before activation completes")

        session.completeActivation(true)
        XCTAssertEqual(synth.spoken.count, 1)
        XCTAssertEqual(synth.spoken[0].text, "4, 2, 1.")
        XCTAssertEqual(synth.spoken[0].preDelay, 0.15, accuracy: 0.0001)
    }

    func testAWarmSpeakIsImmediateWithoutALeadInAndDoesNotActivate() {
        let (output, synth, session, _) = makeOutput()
        speakCold("4, 2, 1.", output, session)
        output.speak("5, 2, 1.")
        XCTAssertEqual(session.activateCount, 1, "the session is already warm")
        XCTAssertEqual(synth.spoken.count, 2, "spoken immediately, no completion needed")
        XCTAssertEqual(synth.spoken[1].text, "5, 2, 1.")
        XCTAssertEqual(synth.spoken[1].preDelay, 0, accuracy: 0.0001)
    }

    func testSeveralSpeaksDuringActivationSpeakOnlyTheLastTextOnce() {
        let (output, synth, session, _) = makeOutput()
        output.speak("one")
        output.speak("two")
        output.speak("three")
        XCTAssertEqual(session.activateCount, 1, "one activation covers all of them")
        XCTAssertTrue(synth.spoken.isEmpty)

        session.completeActivation(true)
        XCTAssertEqual(synth.spoken.map(\.text), ["three"])
        XCTAssertEqual(synth.spoken[0].preDelay, 0.15, accuracy: 0.0001)
    }

    func testAFailedActivationStillSpeaks() {
        let (output, synth, session, _) = makeOutput()
        output.speak("4, 2, 1.")
        session.completeActivation(false)
        XCTAssertEqual(synth.spoken.map(\.text), ["4, 2, 1."])
        XCTAssertEqual(synth.spoken[0].preDelay, 0.15, accuracy: 0.0001)
    }

    func testTheSameActivationCompletingTwiceDoesNotSpeakTwice() {
        let (output, synth, session, _) = makeOutput()
        output.speak("4, 2, 1.")
        session.completeActivation(true)
        session.completeActivation(true, at: 0)
        XCTAssertEqual(synth.spoken.count, 1)
    }

    func testStopDuringActivationSpeaksNothingAndSchedulesDeactivation() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        output.stop()
        XCTAssertEqual(synth.stopCount, 0, "nothing was playing yet")

        session.completeActivation(true)
        XCTAssertTrue(synth.spoken.isEmpty)
        XCTAssertEqual(scheduler.scheduledCount, 1, "the just-activated session is released")
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 1)
    }

    func testASpeakDuringDeactivationWaitsThenReactivates() {
        let (output, synth, session, scheduler) = makeOutput()
        speakCold("4, 2, 1.", output, session)
        synth.onUtteranceEnded?(synth.spoken[0].id)
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 1)

        output.speak("5, 2, 1.")   // the system is still deactivating
        XCTAssertEqual(session.activateCount, 1, "must not activate until deactivation completes")
        XCTAssertEqual(synth.spoken.count, 1)

        session.completeDeactivation(true)
        XCTAssertEqual(session.activateCount, 2, "one extra activation")
        XCTAssertEqual(synth.spoken.count, 1, "still waiting for the activation")

        session.completeActivation(true)
        XCTAssertEqual(synth.spoken.count, 2)
        XCTAssertEqual(synth.spoken[1].text, "5, 2, 1.")
        XCTAssertEqual(synth.spoken[1].preDelay, 0.15, accuracy: 0.0001)
    }

    func testStopDuringDeactivationCancelsTheWaitingReactivation() {
        let (output, synth, session, scheduler) = makeOutput()
        speakCold("4, 2, 1.", output, session)
        synth.onUtteranceEnded?(synth.spoken[0].id)
        scheduler.fire()   // deactivating

        output.speak("5, 2, 1.")   // waits for the deactivation
        output.stop()              // e.g. the scene left the foreground
        session.completeDeactivation(true)
        XCTAssertEqual(session.activateCount, 1, "nothing to say: must not re-activate and duck music")

        // The session is plainly inactive again: the next speak starts cold.
        speakCold("6, 2, 1.", output, session)
        XCTAssertEqual(session.activateCount, 2)
        XCTAssertEqual(synth.spoken.last?.text, "6, 2, 1.")
        XCTAssertEqual(synth.spoken.last?.preDelay ?? 0, 0.15, accuracy: 0.0001)
    }

    func testSpeakingWhileAnotherUtteranceIsInFlightStopsItFirst() {
        let (output, synth, session, _) = makeOutput()
        speakCold("4, 2, 1.", output, session)
        XCTAssertEqual(synth.stopCount, 0)
        output.speak("5, 2, 1.")
        XCTAssertEqual(synth.stopCount, 1)
        XCTAssertEqual(synth.spoken.count, 2)
    }

    func testALateCallbackForACancelledUtteranceIsIgnored() {
        let (output, synth, session, scheduler) = makeOutput()
        speakCold("4, 2, 1.", output, session)
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
        speakCold("4, 2, 1.", output, session)
        synth.onUtteranceEnded?(synth.spoken[0].id)
        XCTAssertEqual(session.deactivateCount, 0, "not before the quiet window elapses")

        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 1)
        session.completeDeactivation(true)

        // The next call starts from an inactive session again.
        speakCold("5, 2, 1.", output, session)
        XCTAssertEqual(session.activateCount, 2)
        XCTAssertEqual(synth.spoken[1].preDelay, 0.15, accuracy: 0.0001)
    }

    func testSpeakingDuringTheQuietWindowCancelsTheDeactivation() {
        let (output, synth, session, scheduler) = makeOutput()
        speakCold("4, 2, 1.", output, session)
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
        speakCold("4, 2, 1.", output, session)
        output.stop()
        XCTAssertEqual(synth.stopCount, 1)
        // The cancel callback for the stopped utterance is stale (no current id).
        synth.onUtteranceEnded?(synth.spoken[0].id)
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 1)
    }

    func testDeactivationIsScheduledAfterTheQuietWindow() {
        let (output, synth, session, scheduler) = makeOutput()
        speakCold("4, 2, 1.", output, session)
        synth.onUtteranceEnded?(synth.spoken[0].id)
        XCTAssertEqual(scheduler.delays, [.seconds(1.2)])
    }

    func testAFailedDeactivationIsRetriedOnceAndTheSessionStaysActiveMeanwhile() {
        let (output, synth, session, scheduler) = makeOutput()
        speakCold("4, 2, 1.", output, session)
        synth.onUtteranceEnded?(synth.spoken[0].id)

        scheduler.fire()   // first attempt
        session.completeDeactivation(false)   // refused: reschedules
        XCTAssertEqual(session.deactivateCount, 1)
        XCTAssertEqual(scheduler.scheduledCount, 1, "a retry is pending")
        output.speak("5, 2, 1.")   // still active: no re-activation, no lead-in
        XCTAssertEqual(session.activateCount, 1)
        XCTAssertEqual(synth.spoken[1].preDelay, 0, accuracy: 0.0001)
        synth.onUtteranceEnded?(synth.spoken[1].id)

        scheduler.fire()   // fresh first attempt: the intervening speak reset the retry flag
        session.completeDeactivation(true)
        XCTAssertEqual(session.deactivateCount, 2)
        speakCold("6, 2, 1.", output, session)
        XCTAssertEqual(session.activateCount, 2)
        XCTAssertEqual(synth.spoken[2].preDelay, 0.15, accuracy: 0.0001)
    }

    func testARetryThatSucceedsReleasesTheSession() {
        let (output, synth, session, scheduler) = makeOutput()
        speakCold("4, 2, 1.", output, session)
        synth.onUtteranceEnded?(synth.spoken[0].id)
        scheduler.fire()
        session.completeDeactivation(false)
        scheduler.fire()
        session.completeDeactivation(true)
        XCTAssertEqual(session.deactivateCount, 2)
        speakCold("5, 2, 1.", output, session)
        XCTAssertEqual(session.activateCount, 2)
        XCTAssertEqual(synth.spoken[1].preDelay, 0.15, accuracy: 0.0001)
    }

    func testTwoFailedDeactivationsGiveUpAndTheNextSpeakActivatesAgain() {
        let (output, synth, session, scheduler) = makeOutput()
        speakCold("4, 2, 1.", output, session)
        synth.onUtteranceEnded?(synth.spoken[0].id)
        scheduler.fire()
        session.completeDeactivation(false)
        scheduler.fire()
        session.completeDeactivation(false)
        XCTAssertEqual(session.deactivateCount, 2)
        XCTAssertEqual(scheduler.scheduledCount, 0, "no third attempt")
        output.speak("5, 2, 1.")
        XCTAssertEqual(session.activateCount, 2, "gave up: tracked as inactive")
        session.completeActivation(true)
        XCTAssertEqual(synth.spoken[1].preDelay, 0.15, accuracy: 0.0001)
    }
}
