import Foundation

/// One row of the Watch's picker: a player the Watch can put in a slot.
public struct WatchPlayerOption: Equatable, Sendable, Identifiable {
    public let entry: SyncedPlayerRef
    public let isMe: Bool

    public init(entry: SyncedPlayerRef, isMe: Bool = false) {
        self.entry = entry
        self.isMe = isMe
    }

    public var id: String {
        entry.savedPlayerID.map { "id:\($0.uuidString)" } ?? "name:\(entry.name.lowercased())"
    }
}

/// Who the Watch has put in the player slots, with no UI so every rule is
/// covered by `swift test`. The slots are fixed (two a side) so switching
/// doubles to singles and back loses nothing; the play mode decides which of
/// them are in play. Empty slots are `nil`.
public struct WatchPlayerSelection: Codable, Equatable, Sendable {
    /// A position in the selection, e.g. Team A's second player.
    public struct Slot: Hashable, Sendable {
        public let team: Team
        public let index: Int

        public init(team: Team, index: Int) {
            self.team = team
            self.index = index
        }

        /// "Team A" in singles, "Team A, player 1" in doubles: the slot's row
        /// title and its VoiceOver name.
        public func title(for mode: PlayMode) -> String {
            let side = TeamNaming.placeholderName(for: team)
            return mode == .singles ? side : "\(side), player \(index + 1)"
        }
    }

    public enum AssignResult: Equatable, Sendable {
        case assigned
        /// The same player is already in another slot in play: nothing changed.
        /// `reason` is the phone's wording.
        case refused(reason: String)
    }

    private static let slotsPerSide = 2

    public private(set) var teamA: [SyncedPlayerRef?]
    public private(set) var teamB: [SyncedPlayerRef?]

    public init(teamA: [SyncedPlayerRef?] = [], teamB: [SyncedPlayerRef?] = []) {
        self.teamA = Self.normalized(teamA)
        self.teamB = Self.normalized(teamB)
    }

    /// Decoding re-applies the rules, so stored data of any shape (too many
    /// slots, long or blank names) still gives a valid selection.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            teamA: try container.decodeIfPresent([SyncedPlayerRef?].self, forKey: .teamA) ?? [],
            teamB: try container.decodeIfPresent([SyncedPlayerRef?].self, forKey: .teamB) ?? []
        )
    }

    /// Exactly two slots, names cleaned (blank becomes empty, long names cut).
    private static func normalized(_ slots: [SyncedPlayerRef?]) -> [SyncedPlayerRef?] {
        var result: [SyncedPlayerRef?] = slots.prefix(slotsPerSide).map { ref in
            ref.flatMap { entry in
                PlayerNameRules.truncated(entry.name).map { SyncedPlayerRef(savedPlayerID: entry.savedPlayerID, name: $0) }
            }
        }
        while result.count < slotsPerSide { result.append(nil) }
        return result
    }

    // MARK: Slots

    /// The slots in play: Team A then Team B, one each in singles, two each in doubles.
    public static func slots(for mode: PlayMode) -> [Slot] {
        let count = WatchMatchPlayers.maxPlayersPerSide(for: mode)
        return [Team.teamA, .teamB].flatMap { team in (0..<count).map { Slot(team: team, index: $0) } }
    }

    public func entry(at slot: Slot) -> SyncedPlayerRef? {
        let slots = slot.team == .teamA ? teamA : teamB
        return slots.indices.contains(slot.index) ? slots[slot.index] : nil
    }

    public var isEmpty: Bool {
        (teamA + teamB).allSatisfy { $0 == nil }
    }

    // MARK: Changing

    /// Puts `entry` in `slot`, unless the same player is already in another
    /// slot in play for `mode` (then nothing changes and the reason says so).
    /// Replacing the slot's own player with itself is fine.
    @discardableResult
    public mutating func assign(_ entry: SyncedPlayerRef, to slot: Slot, mode: PlayMode) -> AssignResult {
        guard let name = PlayerNameRules.truncated(entry.name),
              Self.slots(for: mode).contains(slot) else { return .refused(reason: "") }
        let cleaned = SyncedPlayerRef(savedPlayerID: entry.savedPlayerID, name: name)
        if isUsed(cleaned, excluding: slot, mode: mode) {
            return .refused(reason: PlayerNameRules.duplicateReason(forName: name))
        }
        set(cleaned, at: slot)
        return .assigned
    }

    public mutating func clear(_ slot: Slot) {
        set(nil, at: slot)
    }

    public mutating func clearAll() {
        self = WatchPlayerSelection()
    }

    private mutating func set(_ entry: SyncedPlayerRef?, at slot: Slot) {
        guard (0..<Self.slotsPerSide).contains(slot.index) else { return }
        if slot.team == .teamA { teamA[slot.index] = entry } else { teamB[slot.index] = entry }
    }

    // MARK: Duplicates

    /// Whether `entry` is the same player as one in a slot in play other than
    /// `slot`; the picker disables such a row.
    public func isUsed(_ entry: SyncedPlayerRef, excluding slot: Slot, mode: PlayMode) -> Bool {
        Self.slots(for: mode).contains { other in
            other != slot && self.entry(at: other).map { Self.isSamePlayer($0, entry) } == true
        }
    }

    /// Two entries are the same player when both name a saved player and the
    /// ids match, or when either is a typed name (no id) and the names match
    /// case-insensitively. Two different saved players that share a name
    /// (different ids) stay apart, as on the phone.
    static func isSamePlayer(_ lhs: SyncedPlayerRef, _ rhs: SyncedPlayerRef) -> Bool {
        if let left = lhs.savedPlayerID, let right = rhs.savedPlayerID { return left == right }
        return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedSame
    }

    /// The name of the first player in more than one slot in play, if any
    /// (cannot happen through `assign`; it guards a stored selection).
    public func duplicateName(for mode: PlayMode) -> String? {
        let inPlay = Self.slots(for: mode).compactMap { entry(at: $0) }
        for (index, entry) in inPlay.enumerated()
        where inPlay[(index + 1)...].contains(where: { Self.isSamePlayer(entry, $0) }) {
            return entry.name
        }
        return nil
    }

    // MARK: For a match

    /// The players of a match in `mode`: only the slots in play, empty slots
    /// skipped (a lone second player becomes the first).
    public func matchPlayers(for mode: PlayMode) -> WatchMatchPlayers {
        func side(_ team: Team) -> [SyncedPlayerRef] {
            Self.slots(for: mode).filter { $0.team == team }.compactMap { entry(at: $0) }
        }
        return WatchMatchPlayers(teamA: side(.teamA), teamB: side(.teamB))
    }

    /// "Mike & Sarah vs Ann & Bo" for the Players row on Home; `nil` when
    /// nobody is chosen (the row then shows nothing).
    public func summary(for mode: PlayMode) -> String? {
        let players = matchPlayers(for: mode)
        guard !players.isEmpty else { return nil }
        return "\(players.teamName(for: .teamA)) vs \(players.teamName(for: .teamB))"
    }
}

/// The last selection, remembered like `LastUsedRules`: a court session replays
/// the same players. Nothing is ever pre-filled behind the user's back, so an
/// explicit clear stays cleared.
public struct LastUsedPlayers {
    public static let key = "watchLastUsedPlayers"

    public var selection: WatchPlayerSelection

    private let userDefaults: UserDefaults

    /// Unreadable or missing data is an empty selection.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.selection = userDefaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(WatchPlayerSelection.self, from: $0) }
            ?? WatchPlayerSelection()
    }

    public func save() {
        guard !selection.isEmpty, let data = try? JSONEncoder().encode(selection) else {
            userDefaults.removeObject(forKey: Self.key)
            return
        }
        userDefaults.set(data, forKey: Self.key)
    }
}
