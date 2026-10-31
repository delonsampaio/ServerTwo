import Foundation
import os

/// The ids of synced matches the phone has already dealt with: imported ones
/// AND ones the user deleted. Without the second kind a late resend from the
/// Watch (its acknowledgement was still in flight) would bring a deleted match
/// back. Bounded (oldest dropped first) because it only has to outlive the
/// Watch's resend window, not forever.
///
/// Same shape as `PendingSyncStore`: `Sendable` through the defaults suite
/// NAME, and a process-wide lock around each read-modify-write because the
/// WatchConnectivity queue and the main actor both use it.
public struct SeenMatchIDStore: Sendable {
    public static let defaultsKey = "phoneSeenSyncedMatchIDs"
    public static let defaultCapacity = 500
    private static let lock = OSAllocatedUnfairLock()

    private let suiteName: String?
    private let capacity: Int

    public init(suiteName: String? = nil, capacity: Int = SeenMatchIDStore.defaultCapacity) {
        self.suiteName = suiteName
        self.capacity = max(1, capacity)
    }

    private var userDefaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Oldest first.
    public var ids: [UUID] {
        Self.lock.withLock { read() }
    }

    public func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    public func insert(_ id: UUID) {
        insert(contentsOf: [id])
    }

    public func insert(contentsOf newIDs: [UUID]) {
        Self.lock.withLock {
            var ids = read()
            var changed = false
            for id in newIDs where !ids.contains(id) {
                ids.append(id)
                changed = true
            }
            guard changed else { return }
            if ids.count > capacity { ids.removeFirst(ids.count - capacity) }
            userDefaults.set(ids.map(\.uuidString), forKey: Self.defaultsKey)
        }
    }

    private func read() -> [UUID] {
        (userDefaults.stringArray(forKey: Self.defaultsKey) ?? []).compactMap(UUID.init(uuidString:))
    }
}
