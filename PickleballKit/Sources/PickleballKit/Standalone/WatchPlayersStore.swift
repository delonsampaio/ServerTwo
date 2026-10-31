import Foundation
import os

/// What the Watch must remember about a match's players, because the saved
/// `MatchRecord` only keeps display names and `PendingSyncStore` only ids:
///
/// - the players of the match IN PROGRESS, written when it starts and cleared
///   when it finishes or is abandoned, so a relaunch mid-match keeps the names
///   (the engine's snapshot is left alone);
/// - the players of each SAVED match, written when the match is saved and
///   removed once the phone has acknowledged it (or the match was undone), so
///   the player entries can be put into the payload whenever it is (re)sent.
///
/// Same shape as `PendingSyncStore`: `Sendable` through the defaults suite NAME,
/// and a process-wide lock around each read-modify-write. Bounded: the oldest
/// saved-match entries go first.
public struct WatchPlayersStore: Sendable {
    public static let currentKey = "watchCurrentMatchPlayers"
    public static let savedKey = "watchSavedMatchPlayers"
    public static let defaultCapacity = 100
    private static let lock = OSAllocatedUnfairLock()

    private struct SavedEntry: Codable {
        let matchID: UUID
        let players: WatchMatchPlayers
    }

    private let suiteName: String?
    private let capacity: Int

    public init(suiteName: String? = nil, capacity: Int = WatchPlayersStore.defaultCapacity) {
        self.suiteName = suiteName
        self.capacity = max(1, capacity)
    }

    private var userDefaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    // MARK: Match in progress

    public var currentMatchPlayers: WatchMatchPlayers? {
        Self.lock.withLock {
            userDefaults.data(forKey: Self.currentKey).flatMap { try? JSONDecoder().decode(WatchMatchPlayers.self, from: $0) }
        }
    }

    /// An empty value clears the entry.
    public func setCurrentMatchPlayers(_ players: WatchMatchPlayers) {
        Self.lock.withLock {
            guard !players.isEmpty, let data = try? JSONEncoder().encode(players) else {
                userDefaults.removeObject(forKey: Self.currentKey)
                return
            }
            userDefaults.set(data, forKey: Self.currentKey)
        }
    }

    public func clearCurrentMatchPlayers() {
        setCurrentMatchPlayers(.empty)
    }

    // MARK: Saved matches

    public func players(forSavedMatch id: UUID) -> WatchMatchPlayers? {
        Self.lock.withLock { readSaved().first { $0.matchID == id }?.players }
    }

    /// An empty value removes the entry (nothing to remember).
    public func setPlayers(_ players: WatchMatchPlayers, forSavedMatch id: UUID) {
        Self.lock.withLock {
            var entries = readSaved().filter { $0.matchID != id }
            if !players.isEmpty {
                entries.append(SavedEntry(matchID: id, players: players))
                if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
            }
            writeSaved(entries)
        }
    }

    public func removePlayers(forSavedMatch id: UUID) {
        Self.lock.withLock {
            let entries = readSaved()
            guard entries.contains(where: { $0.matchID == id }) else { return }
            writeSaved(entries.filter { $0.matchID != id })
        }
    }

    /// Drops the entries of every match that is not in `ids` (a match that no
    /// longer exists or was already acknowledged).
    public func prune(keepingSavedMatches ids: Set<UUID>) {
        Self.lock.withLock {
            let entries = readSaved()
            let kept = entries.filter { ids.contains($0.matchID) }
            guard kept.count != entries.count else { return }
            writeSaved(kept)
        }
    }

    private func readSaved() -> [SavedEntry] {
        userDefaults.data(forKey: Self.savedKey).flatMap { try? JSONDecoder().decode([SavedEntry].self, from: $0) } ?? []
    }

    private func writeSaved(_ entries: [SavedEntry]) {
        if entries.isEmpty {
            userDefaults.removeObject(forKey: Self.savedKey)
        } else if let data = try? JSONEncoder().encode(entries) {
            userDefaults.set(data, forKey: Self.savedKey)
        }
    }
}
