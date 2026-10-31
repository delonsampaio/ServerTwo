import Foundation

/// The finished matches this device has saved locally but the iPhone has not
/// yet confirmed receiving. The standalone Watch records each saved match here;
/// the WatchConnectivity queue (a later sub-project) reads `pendingMatchIDs` to
/// know what to send and calls `confirmSynced` once the phone has stored it.
/// A plain ordered list of UUIDs in UserDefaults: tiny, survives relaunches,
/// and the matches themselves stay in SwiftData as the single source of truth.
public struct PendingSyncStore {
    public static let defaultsKey = "watchPendingSyncMatchIDs"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Oldest first, so the queue replays in the order the matches were played.
    public var pendingMatchIDs: [UUID] {
        (userDefaults.stringArray(forKey: Self.defaultsKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    public func isPending(_ id: UUID) -> Bool {
        pendingMatchIDs.contains(id)
    }

    public mutating func markPending(_ id: UUID) {
        var ids = pendingMatchIDs
        guard !ids.contains(id) else { return }
        ids.append(id)
        store(ids)
    }

    public mutating func confirmSynced(_ id: UUID) {
        let ids = pendingMatchIDs
        guard ids.contains(id) else { return }
        store(ids.filter { $0 != id })
    }

    private func store(_ ids: [UUID]) {
        userDefaults.set(ids.map(\.uuidString), forKey: Self.defaultsKey)
    }
}
