import Foundation

extension MatchRepository {
    /// The saved players for the Watch's picker, in a fixed order: "Me" first,
    /// then the order Match Setup suggests (most recently played, then most
    /// matches played), then name (case-insensitive), then id, so the same data
    /// always gives the same list and an unchanged list is not pushed again.
    /// Cleaned and capped like the Watch will do on its side. Names only.
    public func watchPlayerList() throws -> [WatchPlayer] {
        let players = try fetchAllSavedPlayers()
        let usage = Self.playerUsage(players: players, matches: try fetchMatchHistory())
        let meID = try fetchMePlayer()?.id

        func stats(_ player: SavedPlayer) -> (mostRecent: Date, timesPlayed: Int) {
            usage[player.id] ?? (Date.distantPast, 0)
        }
        let ordered = players.sorted { lhs, rhs in
            let lhsIsMe = lhs.id == meID, rhsIsMe = rhs.id == meID
            if lhsIsMe != rhsIsMe { return lhsIsMe }
            let lhsStats = stats(lhs), rhsStats = stats(rhs)
            if lhsStats.mostRecent != rhsStats.mostRecent { return lhsStats.mostRecent > rhsStats.mostRecent }
            if lhsStats.timesPlayed != rhsStats.timesPlayed { return lhsStats.timesPlayed > rhsStats.timesPlayed }
            switch lhs.name.caseInsensitiveCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        // `isMe` only for the one player `fetchMePlayer` resolved, so a
        // transient second "Me" row cannot show two.
        return WatchPlayerList.normalized(ordered.map { WatchPlayer(id: $0.id, name: $0.name, isMe: $0.id == meID) })
    }
}
