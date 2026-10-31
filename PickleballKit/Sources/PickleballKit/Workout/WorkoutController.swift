import Foundation
import Observation

public enum WorkoutPhase: Equatable, Sendable {
    case idle
    /// Authorization or the backend's start is still running.
    case starting
    case running
    /// The match is decided and waiting on Done or Undo.
    case paused
    /// A finish or discard is still running.
    case ending
}

/// Runs one workout per match from the match's lifecycle events. Scoring never
/// waits for it: every event only enqueues work, the work runs one operation
/// at a time in order (so Done followed at once by a new match cannot race a
/// finish against a start), and every failure leaves `phase` at `.idle`
/// without any UI.
///
/// An ended HealthKit session can never be reopened, so the workout is only
/// finished at Done; the deciding point just pauses it and Undo resumes it.
@MainActor
@Observable
public final class WorkoutController {
    public private(set) var phase: WorkoutPhase = .idle
    /// Latest rounded beats per minute; `nil` until a sample arrives, while no
    /// workout runs and while it is paused.
    public private(set) var heartRate: Int?

    @ObservationIgnored private let backend: any WorkoutBackend
    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private var tail: Task<Void, Never>?
    /// Bumped for every session the backend is given callbacks for, so a late
    /// callback from an earlier session cannot touch the current one.
    @ObservationIgnored private var generation = 0

    public init(backend: any WorkoutBackend, isEnabled: @escaping () -> Bool = { WorkoutPreference.isEnabled() }) {
        self.backend = backend
        self.isEnabled = isEnabled
    }

    public func handle(_ event: MatchLifecycleEvent) {
        switch event {
        case .started:
            // Read now, not when the queued work runs: the switch applies to
            // the match as it started.
            guard isEnabled() else { return }
            enqueue { await $0.begin() }
        case .decided:
            enqueue { await $0.pauseIfRunning() }
        case .reopened:
            enqueue { await $0.resumeIfPaused() }
        case .finished(let matchID):
            enqueue { await $0.end(save: true, matchID: matchID) }
        case .abandoned:
            enqueue { await $0.end(save: false, matchID: nil) }
        }
    }

    /// Launch reconciliation, after the session's `resumeIfNeeded`: a session
    /// HealthKit kept from the previous launch either belongs to the match that
    /// came back (resume it) or to one that ended while the app was gone (finish
    /// it so it still reaches Health, without a match id). No session: nothing,
    /// a match whose workout is gone does not get a new one.
    public func recoverAtLaunch(matchIsActive: Bool) async {
        enqueue { await $0.recover(matchIsActive: matchIsActive) }
        await settled()
    }

    /// Returns once everything enqueued so far has run.
    public func settled() async {
        await tail?.value
    }

    // MARK: Queue

    private func enqueue(_ operation: @escaping @MainActor (WorkoutController) async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await operation(self)
        }
    }

    // MARK: Operations (run one at a time)

    private func begin() async {
        guard phase == .idle else { return }
        phase = .starting
        guard await backend.requestAuthorization() else {
            phase = .idle
            return
        }
        let id = nextGeneration()
        do {
            try await backend.start(
                onHeartRate: { [weak self] in self?.receive(heartRate: $0, generation: id) },
                onUnexpectedStop: { [weak self] in self?.sessionStopped(generation: id) }
            )
            // An unexpected stop while starting already reset the phase.
            if phase == .starting { phase = .running }
        } catch {
            clear()
        }
    }

    private func pauseIfRunning() async {
        guard phase == .running else { return }
        await backend.pause()
        // The session may have stopped while pausing.
        guard phase == .running else { return }
        phase = .paused
        heartRate = nil
    }

    private func resumeIfPaused() async {
        guard phase == .paused else { return }
        await backend.resume()
        guard phase == .paused else { return }
        phase = .running
    }

    private func end(save: Bool, matchID: UUID?) async {
        guard phase == .running || phase == .paused else { return }
        phase = .ending
        if save {
            await backend.finish(matchID: matchID)
        } else {
            await backend.discard()
        }
        clear()
    }

    private func recover(matchIsActive: Bool) async {
        guard phase == .idle else { return }
        let id = nextGeneration()
        let found = await backend.recover(
            onHeartRate: { [weak self] in self?.receive(heartRate: $0, generation: id) },
            onUnexpectedStop: { [weak self] in self?.sessionStopped(generation: id) }
        )
        guard found else { return }
        if matchIsActive {
            await backend.resume()
            phase = .running
        } else {
            phase = .ending
            await backend.finish(matchID: nil)
            clear()
        }
    }

    // MARK: Backend callbacks

    private func receive(heartRate bpm: Int, generation id: Int) {
        guard id == generation, phase == .running, heartRate != bpm else { return }
        heartRate = bpm
    }

    private func sessionStopped(generation id: Int) {
        // While ending, the stop is the one the controller asked for.
        guard id == generation, phase != .ending else { return }
        clear()
    }

    private func nextGeneration() -> Int {
        generation += 1
        return generation
    }

    private func clear() {
        phase = .idle
        heartRate = nil
    }
}
