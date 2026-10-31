import Foundation
import os

/// The finished matches this device has saved locally but the iPhone has not
/// yet confirmed receiving. The standalone Watch records each saved match here;
/// the WatchConnectivity queue (a later sub-project) reads `pendingMatchIDs` to
/// know what to send and calls `confirmSynced` once the phone has stored it.
/// A plain ordered list of UUIDs in UserDefaults: tiny, survives relaunches,
/// and the matches themselves stay in SwiftData as the single source of truth.
///
/// `Sendable`, with a process-wide lock around every read-modify-write: the
/// WatchConnectivity delegate will be a second user on another thread, and an
/// unlocked "read the array, change it, write it back" could drop an id. The
/// lock is static (not per instance) because instances are cheap values over
/// the same defaults and must exclude each other.
public struct PendingSyncStore: Sendable {
    public static let defaultsKey = "watchPendingSyncMatchIDs"
    private static let lock = OSAllocatedUnfairLock()

    /// The defaults domain by NAME (nil = the app's standard defaults), not the
    /// `UserDefaults` object: that class is not `Sendable`, and a name lets this
    /// struct be `Sendable` without an escape hatch. `UserDefaults` itself is
    /// thread-safe; only the read-modify-write below needs the lock.
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var userDefaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Oldest first, so the queue replays in the order the matches were played.
    public var pendingMatchIDs: [UUID] {
        Self.lock.withLock { readIDs() }
    }

    public func isPending(_ id: UUID) -> Bool {
        pendingMatchIDs.contains(id)
    }

    public func markPending(_ id: UUID) {
        Self.lock.withLock {
            var ids = readIDs()
            guard !ids.contains(id) else { return }
            ids.append(id)
            store(ids)
        }
    }

    public func confirmSynced(_ id: UUID) {
        Self.lock.withLock {
            let ids = readIDs()
            guard ids.contains(id) else { return }
            store(ids.filter { $0 != id })
        }
    }

    private func readIDs() -> [UUID] {
        (userDefaults.stringArray(forKey: Self.defaultsKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    private func store(_ ids: [UUID]) {
        userDefaults.set(ids.map(\.uuidString), forKey: Self.defaultsKey)
    }
}
