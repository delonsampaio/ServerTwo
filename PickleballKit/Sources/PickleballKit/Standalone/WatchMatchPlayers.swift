import Foundation

/// The players of one Watch match, per side: what the match is named after,
/// what is remembered until the match has synced, and what travels to the
/// iPhone. Plain values (the Watch has no `SavedPlayer` rows).
public struct WatchMatchPlayers: Codable, Sendable, Equatable {
    public static let empty = WatchMatchPlayers()

    public var teamA: [SyncedPlayerRef]
    public var teamB: [SyncedPlayerRef]

    public init(teamA: [SyncedPlayerRef] = [], teamB: [SyncedPlayerRef] = []) {
        self.teamA = teamA
        self.teamB = teamB
    }

    public var isEmpty: Bool { teamA.isEmpty && teamB.isEmpty }

    /// Singles has one player a side, doubles two.
    public static func maxPlayersPerSide(for mode: PlayMode) -> Int {
        mode == .singles ? 1 : 2
    }

    public func players(for team: Team) -> [SyncedPlayerRef] {
        team == .teamA ? teamA : teamB
    }

    /// "Mike & Sarah", or "Team A"/"Team B" when the side has nobody: the same
    /// `TeamNaming` the phone and the saved record use.
    public func teamName(for team: Team) -> String {
        TeamNaming.displayName(forPlayerNames: players(for: team).map(\.name), team: team)
    }

    /// The team name from longest to shortest, for a zone that shows the
    /// longest one that fits: the full name ("Delon Sampaio & Mike Ross"),
    /// first name and last initial ("Delon S. & Mike R."), then first names
    /// only. A step that changes nothing, or that would make two players look
    /// the same ("Mike & Mike"), is left out. The first entry is always `teamName`.
    public func teamNameVariants(for team: Team) -> [String] {
        let names = players(for: team).map(\.name)
        var variants = [teamName(for: team)]
        guard !names.isEmpty else { return variants }
        let steps: [(String) -> String] = [Self.firstNameAndLastInitial, Self.firstName]
        for step in steps {
            let shortened = names.map(step)
            // Two players who read the same once shortened would be confusing.
            guard Set(shortened.map { $0.lowercased() }).count == shortened.count else { continue }
            let candidate = TeamNaming.displayName(forPlayerNames: shortened, team: team)
            if !variants.contains(candidate) { variants.append(candidate) }
        }
        return variants
    }

    private static func words(_ name: String) -> [Substring] {
        name.split(whereSeparator: \.isWhitespace)
    }

    /// "Delon Sampaio" becomes "Delon S."; middle names are dropped.
    private static func firstNameAndLastInitial(_ name: String) -> String {
        let parts = words(name)
        guard parts.count > 1, let initial = parts.last?.first else { return name }
        return "\(parts[0]) \(String(initial).uppercased())."
    }

    private static func firstName(_ name: String) -> String {
        words(name).first.map(String.init) ?? name
    }

    /// Cleaned for a match in `mode`: blank names dropped, names cut to 64
    /// characters, at most one (singles) or two (doubles) a side. This is how a
    /// doubles selection can never leak into a singles match.
    public func sliced(for mode: PlayMode) -> WatchMatchPlayers {
        let limit = Self.maxPlayersPerSide(for: mode)
        func clean(_ refs: [SyncedPlayerRef]) -> [SyncedPlayerRef] {
            var result: [SyncedPlayerRef] = []
            for ref in refs {
                guard let name = PlayerNameRules.truncated(ref.name) else { continue }
                result.append(SyncedPlayerRef(savedPlayerID: ref.savedPlayerID, name: name))
                if result.count == limit { break }
            }
            return result
        }
        return WatchMatchPlayers(teamA: clean(teamA), teamB: clean(teamB))
    }
}
