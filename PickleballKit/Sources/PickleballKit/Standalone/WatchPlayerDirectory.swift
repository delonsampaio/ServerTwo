import Foundation
import Observation

/// The players the Watch can pick from: the iPhone's last list, cached so it
/// works offline, plus names typed on the Watch that the phone has not echoed
/// back yet. Observable so the picker follows a new list arriving.
///
/// Update rule: a phone state WITH a player list replaces the cache (and drops
/// the local additions, which the phone's next list includes once it has the
/// match); a state without one (an old phone) never overwrites it. Names are
/// cut to 64 characters and the list capped at 50.
@MainActor
@Observable
public final class WatchPlayerDirectory {
    public static let playersKey = "watchPhonePlayers"
    public static let localNamesKey = "watchLocalPlayerNames"
    public static let maxLocalNames = 20

    @ObservationIgnored private let suiteName: String?

    /// The phone's list, in the phone's order (Me first).
    public private(set) var phonePlayers: [WatchPlayer]
    /// Names typed on the Watch, newest last.
    public private(set) var localNames: [String]

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        phonePlayers = defaults.data(forKey: Self.playersKey)
            .flatMap { try? JSONDecoder().decode([WatchPlayer].self, from: $0) }
            .map(WatchPlayerList.normalized) ?? []
        localNames = (defaults.stringArray(forKey: Self.localNamesKey) ?? []).compactMap(PlayerNameRules.truncated)
    }

    private var userDefaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Everything the picker lists: the phone's players in order, then the
    /// locally typed names the phone does not have under the same name.
    public var options: [WatchPlayerOption] {
        let fromPhone = phonePlayers.map {
            WatchPlayerOption(entry: SyncedPlayerRef(savedPlayerID: $0.id, name: $0.name), isMe: $0.isMe)
        }
        let local = localNames
            .filter { name in !phonePlayers.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
            .map { WatchPlayerOption(entry: SyncedPlayerRef(name: $0)) }
        return fromPhone + local
    }

    public func apply(_ context: PhoneStateContext) {
        guard let list = context.players else { return }
        phonePlayers = WatchPlayerList.normalized(list)
        localNames = []
        if let data = try? JSONEncoder().encode(phonePlayers) {
            userDefaults.set(data, forKey: Self.playersKey)
        }
        userDefaults.removeObject(forKey: Self.localNamesKey)
    }

    /// What a name typed on the Watch means: the cached player with that name
    /// (case-insensitive, so "mike" links the phone's "Mike" and sends its id),
    /// otherwise a new name with no id. `nil` for a blank name.
    public func resolve(typedName: String) -> SyncedPlayerRef? {
        guard let name = PlayerNameRules.truncated(typedName) else { return nil }
        if let known = options.first(where: { $0.entry.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return known.entry
        }
        return SyncedPlayerRef(name: name)
    }

    /// Adds a typed name to the picker until the phone's next list. Does
    /// nothing for a linked player or a name already listed.
    public func remember(_ entry: SyncedPlayerRef) {
        guard entry.savedPlayerID == nil, let name = PlayerNameRules.truncated(entry.name),
              !options.contains(where: { $0.entry.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        localNames.append(name)
        if localNames.count > Self.maxLocalNames { localNames.removeFirst(localNames.count - Self.maxLocalNames) }
        userDefaults.set(localNames, forKey: Self.localNamesKey)
    }
}
