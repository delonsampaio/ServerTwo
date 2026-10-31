import Foundation

/// The HealthKit side of a match workout, behind a protocol so the lifecycle
/// rules in `WorkoutController` are unit-tested here without HealthKit. The
/// Watch target provides the real implementation.
///
/// A backend never throws at the controller except from `start`: pause,
/// resume, finish and discard are best effort (a failure is logged by the
/// backend and the match carries on). The two callbacks are plain main-actor
/// closures, so the backend's own HealthKit delegates only have to hop to the
/// main actor with plain values.
@MainActor
public protocol WorkoutBackend: AnyObject {
    /// Asks for the Health permissions (a no-op once decided). `false` means no
    /// workout can be recorded: unavailable, or workout sharing not allowed.
    func requestAuthorization() async -> Bool

    /// Starts a pickleball workout. `onHeartRate` gets rounded beats per
    /// minute; `onUnexpectedStop` fires if the session fails or ends without
    /// the controller asking (for example another workout app took over).
    func start(
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) async throws

    /// Freezes the workout clock; `resume` continues the same session.
    func pause() async
    func resume() async

    /// Ends the workout and saves it to Health, tagged with the match id when
    /// there is one.
    func finish(matchID: UUID?) async

    /// Ends the workout and throws it away.
    func discard() async

    /// Re-attaches to a session left running by a previous launch. `false` when
    /// there was none.
    func recover(
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) async -> Bool
}
