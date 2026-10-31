import Foundation
import HealthKit
import os
import PickleballKit

/// The real workout backend: one `HKWorkoutSession` and its live builder per
/// match, `.pickleball`, no GPS. All of HealthKit's callbacks arrive through
/// `WorkoutDelegateAdapter` on a background queue and hop back here as plain
/// values; the controller in the kit decides when each method below is called.
@MainActor
final class HealthKitWorkoutBackend: WorkoutBackend {
    private let store = HKHealthStore()
    private let log = Logger(subsystem: "com.delonsampaio.ServerTwo", category: "Workout")

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// HealthKit holds its delegates weakly, so the adapter lives here.
    private var delegate: WorkoutDelegateAdapter?
    private var onHeartRate: (@MainActor (Int) -> Void)?
    private var onUnexpectedStop: (@MainActor () -> Void)?
    /// Set while this backend ends the session itself, so the session's own
    /// "ended" callback is not mistaken for an outside stop.
    private var isEnding = false
    /// Which attachment the current session belongs to: a late callback from
    /// an earlier session must not act on the next match's workout.
    private var attachmentID = 0

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            log.error("Health authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        // Read access is never reported (a denied heart rate just yields no
        // samples); only the workout write decides whether to record at all.
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func start(
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .pickleball
        configuration.locationType = .unknown

        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        attach(session: session, builder: builder, onHeartRate: onHeartRate, onUnexpectedStop: onUnexpectedStop)
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)

        let startDate = Date()
        session.startActivity(with: startDate)
        do {
            try await builder.beginCollection(at: startDate)
        } catch {
            log.error("Workout start failed: \(error.localizedDescription, privacy: .public)")
            isEnding = true
            session.end()
            builder.discardWorkout()
            release()
            throw error
        }
    }

    func pause() async {
        session?.pause()
    }

    func resume() async {
        session?.resume()
    }

    /// `end()`, then `endCollection`, then `finishWorkout`, the order HealthKit
    /// documents. A nil workout with no error is success: the watch is
    /// passcode-locked and HealthKit saves it once it unlocks.
    func finish(matchID: UUID?) async {
        guard let session, let builder else { return }
        isEnding = true
        do {
            if let matchID {
                // Lets the saved workout be matched to the match on the phone.
                try await builder.addMetadata([HKMetadataKeyExternalUUID: matchID.uuidString])
            }
        } catch {
            log.error("Workout metadata failed: \(error.localizedDescription, privacy: .public)")
        }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
        } catch {
            log.error("Workout finish failed: \(error.localizedDescription, privacy: .public)")
        }
        release()
    }

    func discard() async {
        guard let session, let builder else { return }
        isEnding = true
        session.end()
        do {
            try await builder.endCollection(at: Date())
        } catch {
            log.error("Workout end before discard failed: \(error.localizedDescription, privacy: .public)")
        }
        builder.discardWorkout()
        release()
    }

    /// Only the delegates are re-attached: the recovered builder keeps the data
    /// source it had, and replacing it would restart the sensors.
    func recover(
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let recovered: HKWorkoutSession?
        do {
            recovered = try await store.recoverActiveWorkoutSession()
        } catch {
            log.error("Workout recovery failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard let recovered else { return false }
        attach(
            session: recovered, builder: recovered.associatedWorkoutBuilder(),
            onHeartRate: onHeartRate, onUnexpectedStop: onUnexpectedStop
        )
        return true
    }

    // MARK: Private

    private func attach(
        session: HKWorkoutSession,
        builder: HKLiveWorkoutBuilder,
        onHeartRate: @escaping @MainActor (Int) -> Void,
        onUnexpectedStop: @escaping @MainActor () -> Void
    ) {
        attachmentID += 1
        let id = attachmentID
        let adapter = WorkoutDelegateAdapter(
            onHeartRate: { [weak self] bpm in
                Task { @MainActor in
                    guard let self, self.attachmentID == id else { return }
                    self.onHeartRate?(bpm)
                }
            },
            onSessionEnded: { [weak self] in
                Task { @MainActor in
                    guard let self, self.attachmentID == id else { return }
                    self.sessionEnded()
                }
            }
        )
        session.delegate = adapter
        builder.delegate = adapter
        self.session = session
        self.builder = builder
        self.delegate = adapter
        self.onHeartRate = onHeartRate
        self.onUnexpectedStop = onUnexpectedStop
        isEnding = false
    }

    /// The session failed or ended. Ours (finish, discard, a failed start) is
    /// ignored; anything else means the workout is gone (another workout app,
    /// a failure), so the half-built workout is dropped and the controller told.
    private func sessionEnded() {
        guard !isEnding, let builder else { return }
        log.error("Workout session ended outside the app")
        let stopped = onUnexpectedStop
        builder.discardWorkout()
        release()
        stopped?()
    }

    private func release() {
        session?.delegate = nil
        builder?.delegate = nil
        session = nil
        builder = nil
        delegate = nil
        onHeartRate = nil
        onUnexpectedStop = nil
        isEnding = false
    }
}

/// HealthKit calls these delegate methods on its own background queue, so every
/// one is `nonisolated` and only forwards plain values through `Sendable`
/// closures that hop to the main actor. The heart-rate statistic is read into
/// an `Int` here, on that queue, because `HKStatistics` is not `Sendable`.
nonisolated final class WorkoutDelegateAdapter: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let onHeartRate: @Sendable (Int) -> Void
    private let onSessionEnded: @Sendable () -> Void

    init(onHeartRate: @escaping @Sendable (Int) -> Void, onSessionEnded: @escaping @Sendable () -> Void) {
        self.onHeartRate = onHeartRate
        self.onSessionEnded = onSessionEnded
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .stopped || toState == .ended { onSessionEnded() }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        onSessionEnded()
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let quantity = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()
        else { return }
        let perMinute = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        guard perMinute.isFinite else { return }
        onHeartRate(Int(perMinute.rounded()))
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
