import XCTest
@testable import PickleballKit

/// Suspends an operation of the fake backend until the test lets it go, so the
/// ordering of queued work can be observed.
@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class FakeWorkoutBackend: WorkoutBackend {
    enum Call: Equatable {
        case authorize, start, pause, resume, finish(UUID?), discard, recover
    }

    struct StartFailure: Error {}

    var calls: [Call] = []
    var authorizationResult = true
    var startError: Error?
    var recoverResult = false
    var startGate: Gate?
    var finishGate: Gate?
    var heartRate: (@MainActor (Int) -> Void)?
    var unexpectedStop: (@MainActor () -> Void)?

    func requestAuthorization() async -> Bool {
        calls.append(.authorize)
        return authorizationResult
    }

    func start(
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) async throws {
        calls.append(.start)
        await startGate?.wait()
        if let startError { throw startError }
        heartRate = onHeartRate
        unexpectedStop = onUnexpectedStop
    }

    func pause() async { calls.append(.pause) }
    func resume() async { calls.append(.resume) }

    func finish(matchID: UUID?) async {
        calls.append(.finish(matchID))
        await finishGate?.wait()
    }

    func discard() async { calls.append(.discard) }

    func recover(
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) async -> Bool {
        calls.append(.recover)
        guard recoverResult else { return false }
        heartRate = onHeartRate
        unexpectedStop = onUnexpectedStop
        return true
    }
}

@MainActor
final class WorkoutControllerTests: XCTestCase {
    private var backend = FakeWorkoutBackend()
    private var enabled = true
    private var controller: WorkoutController!

    override func setUp() async throws {
        backend = FakeWorkoutBackend()
        enabled = true
        controller = WorkoutController(backend: backend, isEnabled: { [unowned self] in self.enabled })
    }

    /// Lets queued work run until `condition` holds (bounded, so a bug fails
    /// instead of hanging).
    private func yield(until condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { await Task.yield() }
    }

    private func yieldALot() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func startMatch() async {
        controller.handle(.started)
        await controller.settled()
    }

    // MARK: Start

    func testStartsAWorkoutWhenEnabledAndAuthorised() async {
        await startMatch()
        XCTAssertEqual(backend.calls, [.authorize, .start])
        XCTAssertEqual(controller.phase, .running)
    }

    func testTheSwitchOffMeansNoAuthorizationAndNoSession() async {
        enabled = false
        await startMatch()
        controller.handle(.decided)
        controller.handle(.finished(matchID: UUID()))
        await controller.settled()
        XCTAssertEqual(backend.calls, [])
        XCTAssertEqual(controller.phase, .idle)
    }

    func testTheSwitchIsReadWhenTheMatchStarts() async {
        await startMatch()
        enabled = false  // turned off mid-match: this match keeps its workout
        controller.handle(.finished(matchID: UUID()))
        await controller.settled()
        XCTAssertEqual(backend.calls.count, 3)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testRefusedAuthorizationLeavesTheWorkoutIdleAndLaterEventsDoNothing() async {
        backend.authorizationResult = false
        await startMatch()
        XCTAssertEqual(controller.phase, .idle)
        controller.handle(.decided)
        controller.handle(.reopened)
        controller.handle(.finished(matchID: UUID()))
        controller.handle(.abandoned)
        await controller.settled()
        XCTAssertEqual(backend.calls, [.authorize])
        XCTAssertEqual(controller.phase, .idle)
    }

    func testAStartThatThrowsLeavesTheWorkoutIdle() async {
        backend.startError = FakeWorkoutBackend.StartFailure()
        await startMatch()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.heartRate)
        controller.handle(.finished(matchID: UUID()))
        await controller.settled()
        XCTAssertEqual(backend.calls, [.authorize, .start])
    }

    // MARK: Follows the match

    func testDecidedPausesAndReopenedResumes() async {
        await startMatch()
        controller.handle(.decided)
        await controller.settled()
        XCTAssertEqual(controller.phase, .paused)
        controller.handle(.reopened)
        await controller.settled()
        XCTAssertEqual(controller.phase, .running)
        XCTAssertEqual(backend.calls, [.authorize, .start, .pause, .resume])
    }

    func testReopenedWithoutAPauseAndDecidedTwiceDoNothingExtra() async {
        await startMatch()
        controller.handle(.reopened)
        controller.handle(.decided)
        controller.handle(.decided)
        await controller.settled()
        XCTAssertEqual(backend.calls, [.authorize, .start, .pause])
    }

    func testFinishedFinishesWithTheMatchIDAndClearsTheState() async {
        let id = UUID()
        await startMatch()
        backend.heartRate?(120)
        controller.handle(.decided)
        controller.handle(.finished(matchID: id))
        await controller.settled()
        XCTAssertEqual(backend.calls, [.authorize, .start, .pause, .finish(id)])
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.heartRate)
    }

    func testAbandonedDiscards() async {
        await startMatch()
        controller.handle(.abandoned)
        await controller.settled()
        XCTAssertEqual(backend.calls, [.authorize, .start, .discard])
        XCTAssertEqual(controller.phase, .idle)
    }

    func testAFinishedWorkoutIsNotFinishedAgain() async {
        await startMatch()
        controller.handle(.finished(matchID: UUID()))
        controller.handle(.finished(matchID: UUID()))
        controller.handle(.abandoned)
        await controller.settled()
        XCTAssertEqual(backend.calls.count, 3)
    }

    // MARK: Ordering

    func testDoneQueuedBehindAStillRunningStartRunsAfterItFinishes() async {
        let id = UUID()
        let gate = Gate()
        backend.startGate = gate
        controller.handle(.started)
        controller.handle(.decided)
        controller.handle(.finished(matchID: id))
        await yield { backend.calls.contains(.start) }
        await yieldALot()
        XCTAssertEqual(backend.calls, [.authorize, .start], "nothing runs while the start is in flight")
        XCTAssertEqual(controller.phase, .starting)

        gate.open()
        await controller.settled()
        XCTAssertEqual(backend.calls, [.authorize, .start, .pause, .finish(id)])
        XCTAssertEqual(controller.phase, .idle)
    }

    func testASecondMatchWaitsForTheFirstFinish() async {
        let gate = Gate()
        backend.finishGate = gate
        await startMatch()
        controller.handle(.finished(matchID: UUID()))
        await yield { backend.calls.count == 3 }
        controller.handle(.started)  // the next match, right after Done
        await yieldALot()
        XCTAssertEqual(backend.calls.filter { $0 == .authorize }.count, 1, "no second start while finishing")

        gate.open()
        await controller.settled()
        XCTAssertEqual(backend.calls.suffix(2), [.authorize, .start])
        XCTAssertEqual(controller.phase, .running)
    }

    // MARK: Failure and heart rate

    func testAnUnexpectedStopClearsTheStateSilently() async {
        await startMatch()
        backend.heartRate?(130)
        XCTAssertEqual(controller.heartRate, 130)
        backend.unexpectedStop?()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.heartRate)

        // The rest of that match does nothing, the next one gets a workout.
        controller.handle(.decided)
        controller.handle(.finished(matchID: UUID()))
        await controller.settled()
        XCTAssertEqual(backend.calls, [.authorize, .start])
        await startMatch()
        XCTAssertEqual(controller.phase, .running)
    }

    func testHeartRateUpdates() async {
        await startMatch()
        XCTAssertNil(controller.heartRate)
        backend.heartRate?(98)
        XCTAssertEqual(controller.heartRate, 98)
        backend.heartRate?(101)
        XCTAssertEqual(controller.heartRate, 101)
    }

    func testHeartRateIsHiddenWhilePausedAndAfterTheWorkoutEnds() async {
        await startMatch()
        backend.heartRate?(110)
        controller.handle(.decided)
        await controller.settled()
        XCTAssertNil(controller.heartRate)
        backend.heartRate?(111)  // a straggler while paused
        XCTAssertNil(controller.heartRate)
    }

    func testALateCallbackFromAnEarlierSessionIsIgnored() async {
        await startMatch()
        let oldHeartRate = backend.heartRate
        let oldStop = backend.unexpectedStop
        controller.handle(.finished(matchID: UUID()))
        await startMatch()
        oldHeartRate?(150)
        XCTAssertNil(controller.heartRate)
        oldStop?()
        XCTAssertEqual(controller.phase, .running)
    }

    // MARK: Launch recovery

    func testRecoveredSessionWithAnActiveMatchResumes() async {
        backend.recoverResult = true
        await controller.recoverAtLaunch(matchIsActive: true)
        XCTAssertEqual(backend.calls, [.recover, .resume])
        XCTAssertEqual(controller.phase, .running)
        backend.heartRate?(90)
        XCTAssertEqual(controller.heartRate, 90)
    }

    func testRecoveredSessionWithNoMatchIsFinishedWithoutAnID() async {
        backend.recoverResult = true
        await controller.recoverAtLaunch(matchIsActive: false)
        XCTAssertEqual(backend.calls, [.recover, .finish(nil)])
        XCTAssertEqual(controller.phase, .idle)
    }

    func testNothingRecoveredDoesNothing() async {
        await controller.recoverAtLaunch(matchIsActive: true)
        XCTAssertEqual(backend.calls, [.recover])
        XCTAssertEqual(controller.phase, .idle)
    }

    func testRecoveryRunsEvenWithTheSwitchOff() async {
        enabled = false
        backend.recoverResult = true
        await controller.recoverAtLaunch(matchIsActive: false)
        XCTAssertEqual(backend.calls, [.recover, .finish(nil)])
    }

    func testARecoveredWorkoutIsFinishedByDoneLikeAnyOther() async {
        let id = UUID()
        backend.recoverResult = true
        await controller.recoverAtLaunch(matchIsActive: true)
        controller.handle(.finished(matchID: id))
        await controller.settled()
        XCTAssertEqual(backend.calls, [.recover, .resume, .finish(id)])
    }

    // MARK: Preference

    func testThePreferenceDefaultsToOn() {
        let suite = "WorkoutPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(WorkoutPreference.isEnabled(userDefaults: defaults))
        defaults.set(false, forKey: WorkoutPreference.key)
        XCTAssertFalse(WorkoutPreference.isEnabled(userDefaults: defaults))
        defaults.set(true, forKey: WorkoutPreference.key)
        XCTAssertTrue(WorkoutPreference.isEnabled(userDefaults: defaults))
        XCTAssertEqual(WorkoutPreference.key, "watchRecordWorkout")
    }
}
