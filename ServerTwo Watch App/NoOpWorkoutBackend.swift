import Foundation
import PickleballKit

/// Demo and automation launches: no Health prompt over a screenshot and no
/// workout from a scripted match. Authorization is refused, so the controller
/// never starts anything.
@MainActor
final class NoOpWorkoutBackend: WorkoutBackend {
    private struct NoWorkout: Error {}

    func requestAuthorization() async -> Bool { false }
    func start(
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) async throws { throw NoWorkout() }
    func pause() async {}
    func resume() async {}
    func finish(matchID: UUID?) async {}
    func discard() async {}
    func recover(
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) async -> Bool { false }
}
