import Foundation
import os

/// Keeps one Live Activity in step with the live match. It never throws and
/// never blocks: a disabled or failing Live Activity must not affect scoring,
/// so every problem is logged and swallowed.
///
/// ActivityKit calls are `async`, so they run on one serial chain (each waits
/// for the previous one). That is what makes "last write wins" mean the last
/// CALL: a fast score-then-undo can never be overtaken by a slower earlier
/// update, and an update can never race an `end`.
@MainActor
final class LiveActivityController {
    typealias State = PickleballActivityAttributes.ContentState

    /// A finished match stays on the Lock Screen this long (the system default
    /// would keep it for hours), enough to glance at the final score.
    static let finishedDismissalDelay: TimeInterval = 5 * 60
    /// If the app stops updating (crash, force quit mid-match) the system marks
    /// the activity stale after this long, and the view says so. Long on
    /// purpose: a break between games must not look like a problem while the
    /// app is fine, and it stays well under ActivityKit's own 8 hour limit.
    static let staleAfter: TimeInterval = 3 * 60 * 60

    private static let log = Logger(subsystem: "com.delonsampaio.ServerTwo", category: "LiveActivity")

    private let host: any LiveActivityHosting
    private let now: () -> Date
    private var handle: (any LiveActivityHandle)?
    /// Whether a match is currently being mirrored. Stays true when the first
    /// request failed or Live Activities were off, so one later attempt is
    /// possible; false after `end`/`endAll`, which is what stops a re-request
    /// after the match is over.
    private var isDriving = false
    /// The current match's static attributes, kept for the one retry.
    private var attributes: PickleballActivityAttributes?
    /// One re-attempt at `Activity.request` per match (see `retryIfNeeded`):
    /// enough to recover from a start that failed at a bad moment (e.g. the app
    /// was not yet foreground) without ever looping on a persistent failure.
    private var retriesLeft = 0
    /// The last state handed to the host, to skip identical updates.
    private var lastState: State?
    private var tail: Task<Void, Never>?

    init(host: any LiveActivityHosting, now: @escaping () -> Date = Date.init) {
        self.host = host
        self.now = now
    }

    /// A new match became active: end any leftover activity, then start one.
    func begin(attributes: PickleballActivityAttributes, state: State) {
        startDriving(attributes: attributes, state: state)
        guard host.areActivitiesEnabled else { return }
        enqueue { [self] in
            // A leftover from a force quit would otherwise sit next to the new one.
            await endEveryRunningActivity()
            handle = startActivity(attributes: attributes, state: state)
        }
    }

    /// A match was resumed after a relaunch. The system keeps a Live Activity
    /// alive across a crash, so attach to the one that belongs to this match
    /// rather than stacking a second; replace anything else.
    func resume(attributes: PickleballActivityAttributes, state: State) {
        startDriving(attributes: attributes, state: state)
        guard host.areActivitiesEnabled else { return }
        enqueue { [self] in
            let running = host.runningActivities
            // Static attributes are fixed for an activity's life, so a survivor
            // with different names is another match's and must not be reused.
            if let index = running.firstIndex(where: { $0.attributes == attributes }) {
                handle = running[index]
                await running[index].update(state, staleDate: staleDate())
                for (other, activity) in running.enumerated() where other != index {
                    await activity.end(nil, dismissal: .immediate)
                }
            } else {
                await endEveryRunningActivity()
                handle = startActivity(attributes: attributes, state: state)
            }
        }
    }

    /// Pushes a new state, but only when something the Lock Screen shows changed.
    /// If no activity exists (the start failed, or Live Activities were off) this
    /// is also the one chance to try starting it again.
    func update(_ state: State) {
        guard isDriving, state != lastState else { return }
        lastState = state
        enqueue { [self] in
            if let handle {
                await handle.update(state, staleDate: staleDate())
            } else {
                retryStart(with: state)
            }
        }
    }

    /// Called when the app becomes active: the same single retry as `update`,
    /// for a match whose activity never started.
    func retryIfNeeded() {
        guard isDriving, handle == nil, retriesLeft > 0, let state = lastState else { return }
        enqueue { [self] in
            if handle == nil { retryStart(with: state) }
        }
    }

    func end(finalState: State?, dismissal: LiveActivityDismissal) {
        guard isDriving else { return }
        isDriving = false
        lastState = nil
        attributes = nil
        enqueue { [self] in
            let ending = handle
            handle = nil
            await ending?.end(finalState, dismissal: dismissal)
        }
    }

    /// There is no match, so no activity should be running: cleans up one a
    /// force quit stranded on the Lock Screen.
    func endAll() {
        guard host.areActivitiesEnabled else { return }
        isDriving = false
        lastState = nil
        attributes = nil
        enqueue { [self] in
            handle = nil
            await endEveryRunningActivity()
        }
    }

    /// For tests: returns once every queued ActivityKit call has run.
    func waitUntilIdle() async {
        await tail?.value
    }

    private func startDriving(attributes: PickleballActivityAttributes, state: State) {
        isDriving = true
        self.attributes = attributes
        lastState = state
        retriesLeft = 1
    }

    /// Runs inside the serial chain. A swipe-dismissed activity still has a
    /// handle, so it never lands here: only "never started" does.
    private func retryStart(with state: State) {
        guard isDriving, handle == nil, retriesLeft > 0, let attributes, host.areActivitiesEnabled else { return }
        retriesLeft -= 1
        handle = startActivity(attributes: attributes, state: state)
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await operation()
        }
    }

    private func staleDate() -> Date {
        now().addingTimeInterval(Self.staleAfter)
    }

    private func endEveryRunningActivity() async {
        for running in host.runningActivities {
            await running.end(nil, dismissal: .immediate)
        }
    }

    private func startActivity(attributes: PickleballActivityAttributes, state: State) -> (any LiveActivityHandle)? {
        do {
            return try host.request(attributes: attributes, state: state, staleDate: staleDate())
        } catch {
            // The match carries on without it.
            Self.log.error("Could not start the Live Activity: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
