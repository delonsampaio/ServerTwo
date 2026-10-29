import Foundation

/// How long a Live Activity stays on the Lock Screen after it ends.
nonisolated enum LiveActivityDismissal: Hashable {
    case immediate
    case afterDelay(TimeInterval)
}

/// One running Live Activity, as the controller sees it. A protocol (rather
/// than `Activity<...>` directly) so the controller's logic is unit-tested
/// with a recording fake and UI tests never touch ActivityKit.
@MainActor
protocol LiveActivityHandle {
    /// The static attributes the activity was started with, so a relaunch can
    /// tell whether a surviving activity belongs to the match being resumed.
    var attributes: PickleballActivityAttributes { get }
    func update(_ state: PickleballActivityAttributes.ContentState, staleDate: Date?) async
    func end(_ finalState: PickleballActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async
}

@MainActor
protocol LiveActivityHosting {
    /// False when the user turned Live Activities off for the app (or for the
    /// whole device). Not an error: the app simply does without.
    var areActivitiesEnabled: Bool { get }
    var runningActivities: [any LiveActivityHandle] { get }
    func request(
        attributes: PickleballActivityAttributes,
        state: PickleballActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> any LiveActivityHandle
}

/// Used by UI tests and as the default for unit tests that do not care about
/// Live Activities: nothing is enabled, so every controller call is a no-op.
struct NoOpLiveActivityHost: LiveActivityHosting {
    var areActivitiesEnabled: Bool { false }
    var runningActivities: [any LiveActivityHandle] { [] }

    struct Unavailable: Error {}

    func request(
        attributes: PickleballActivityAttributes,
        state: PickleballActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> any LiveActivityHandle {
        throw Unavailable()
    }
}
