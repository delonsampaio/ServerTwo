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
