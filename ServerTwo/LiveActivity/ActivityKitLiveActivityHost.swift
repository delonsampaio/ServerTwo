#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The real ActivityKit implementation. Local-only: `pushType` is nil, because
/// the app has no backend and every update comes from the live scoring session.
struct ActivityKitLiveActivityHost: LiveActivityHosting {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var runningActivities: [any LiveActivityHandle] {
        Activity<PickleballActivityAttributes>.activities.map(ActivityKitHandle.init)
    }

    func request(
        attributes: PickleballActivityAttributes,
        state: PickleballActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> any LiveActivityHandle {
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: staleDate),
            pushType: nil
        )
        return ActivityKitHandle(activity: activity)
    }
}

/// `Activity` is not Sendable, and its `update`/`end` are `@concurrent`, so an
/// instance stored on the main actor cannot be awaited on without a data-race
/// error. The handle therefore keeps only the activity's id and attributes and
/// looks the live instance up again for each call: a fresh value is not tied
/// to any actor, so ActivityKit can use it freely.
private struct ActivityKitHandle: LiveActivityHandle {
    let id: String
    let attributes: PickleballActivityAttributes

    init(activity: Activity<PickleballActivityAttributes>) {
        id = activity.id
        attributes = activity.attributes
    }

    private nonisolated func liveActivity() -> Activity<PickleballActivityAttributes>? {
        Activity<PickleballActivityAttributes>.activities.first { $0.id == id }
    }

    func update(_ state: PickleballActivityAttributes.ContentState, staleDate: Date?) async {
        await liveActivity()?.update(ActivityContent(state: state, staleDate: staleDate))
    }

    func end(_ finalState: PickleballActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async {
        let policy: ActivityUIDismissalPolicy = switch dismissal {
        case .immediate: .immediate
        case .afterDelay(let seconds): .after(Date().addingTimeInterval(seconds))
        }
        await liveActivity()?.end(
            finalState.map { ActivityContent(state: $0, staleDate: nil) },
            dismissalPolicy: policy
        )
    }
}
#endif
