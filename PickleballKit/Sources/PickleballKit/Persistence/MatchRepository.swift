import SwiftData
import Foundation

public enum MatchRepositoryError: Error, Equatable {
    case matchNotOver
}

/// A match reconstructed from a saved in-progress snapshot, paired with
/// the match's original start time (the engine itself doesn't track
/// wall-clock time, so the repository carries it alongside).
public struct ResumedMatch {
    public let match: PickleballMatch
    public let startedAt: Date
}

/// Wraps all SwiftData access for match persistence. UI code should never
/// touch `ModelContext` directly — it goes through this type instead.
public final class MatchRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: In-progress snapshot (crash recovery)

    public func saveInProgressSnapshot(for match: PickleballMatch, startedAt: Date) throws {
        let data = try JSONEncoder().encode(match.snapshot(startedAt: startedAt))
        try clearInProgressSnapshot()
        let record = InProgressGameState(updatedAt: Date(), snapshotData: data)
        modelContext.insert(record)
        try modelContext.save()
    }

    public func loadInProgressMatch(proUnlocked: Bool, demoPointCap: Int?) throws -> ResumedMatch? {
        let descriptor = FetchDescriptor<InProgressGameState>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let existing = try modelContext.fetch(descriptor)
        guard let record = existing.first else { return nil }
        let snapshot = try JSONDecoder().decode(MatchSnapshot.self, from: record.snapshotData)
        let match = PickleballMatch(resuming: snapshot, proUnlocked: proUnlocked, demoPointCap: demoPointCap)
        guard !match.isMatchOver else {
            // A snapshot can only reach "match over" if the app crashed or
            // was force-quit after the match-deciding point but before
            // saveCompletedMatch's clearInProgressSnapshot() ran. There's
            // nothing useful to resume — clear it so it can't resurface
            // and be mistaken for a live match (or saved to history twice).
            try clearInProgressSnapshot()
            return nil
        }
        return ResumedMatch(match: match, startedAt: snapshot.startedAt)
    }

    public func clearInProgressSnapshot() throws {
        let existing = try modelContext.fetch(FetchDescriptor<InProgressGameState>())
        for stale in existing {
            modelContext.delete(stale)
        }
        try modelContext.save()
    }

    // MARK: Completed match history

    @discardableResult
    public func saveCompletedMatch(
        _ match: PickleballMatch,
        teamAName: String,
        teamBName: String,
        startedAt: Date,
        completedAt: Date = Date(),
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = []
    ) throws -> MatchRecord {
        guard let winner = match.matchWinner else {
            throw MatchRepositoryError.matchNotOver
        }

        let configurationData = try JSONEncoder().encode(match.configuration)
        let record = MatchRecord(
            startedAt: startedAt,
            completedAt: completedAt,
            matchFormat: match.matchFormat,
            winningTeam: winner,
            configurationData: configurationData
        )

        // Every object in the graph is inserted explicitly rather than
        // relying on SwiftData to cascade-insert objects reachable only
        // through a relationship — that cascade is unreliable for larger
        // nested graphs (observed dropping PointEvent rows nondeterministically
        // when only the root MatchRecord was inserted).
        modelContext.insert(record)

        let teamASide = TeamSide(team: .teamA, displayName: teamAName)
        let teamBSide = TeamSide(team: .teamB, displayName: teamBName)
        teamASide.match = record
        teamBSide.match = record
        teamASide.players = teamAPlayers
        teamBSide.players = teamBPlayers
        record.teamSides = [teamASide, teamBSide]
        modelContext.insert(teamASide)
        modelContext.insert(teamBSide)

        var gameRecords: [GameRecord] = []
        var gameNumber = 0
        for game in match.completedGames {
            guard let gameWinner = game.gameWinner else { continue }
            gameNumber += 1
            let gameRecord = GameRecord(
                gameNumber: gameNumber,
                teamAFinalScore: game.state.teamAScore,
                teamBFinalScore: game.state.teamBScore,
                winningTeam: gameWinner
            )
            gameRecord.match = record
            modelContext.insert(gameRecord)

            let events = derivePointEvents(history: game.history, finalState: game.state)
            gameRecord.points = events.map { event in
                let point = PointEvent(
                    sequenceNumber: event.sequenceNumber,
                    scoringTeam: event.scoringTeam,
                    teamAScoreAfter: event.teamAScoreAfter,
                    teamBScoreAfter: event.teamBScoreAfter
                )
                point.game = gameRecord
                modelContext.insert(point)
                return point
            }
            gameRecords.append(gameRecord)
        }
        record.games = gameRecords

        try modelContext.save()

        // The match this just persisted to history can no longer be the
        // "live in-progress match" — clear its crash-recovery snapshot so
        // loadInProgressMatch can't resurface a finished match (which would
        // both read as "currently playing" and risk being saved twice).
        try clearInProgressSnapshot()

        return record
    }

    public func fetchMatchHistory() throws -> [MatchRecord] {
        let descriptor = FetchDescriptor<MatchRecord>(
            sortBy: [
                SortDescriptor(\.completedAt, order: .reverse),
                SortDescriptor(\.id)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: Saved Players

    public func fetchAllSavedPlayers() throws -> [SavedPlayer] {
        try modelContext.fetch(FetchDescriptor<SavedPlayer>())
    }

    public func fetchMePlayer() throws -> SavedPlayer? {
        try fetchAllSavedPlayers().first { $0.isMe }
    }

    /// Finds-or-creates a `SavedPlayer` by exact, trimmed, case-sensitive
    /// name match. Returns `nil` for blank/whitespace-only input without
    /// creating anything — callers must never upsert an empty field.
    @discardableResult
    public func upsertSavedPlayer(name: String) throws -> SavedPlayer? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = try fetchAllSavedPlayers().first(where: { $0.name == trimmed }) {
            return existing
        }
        let player = SavedPlayer(name: trimmed)
        modelContext.insert(player)
        try modelContext.save()
        return player
    }

    public func deleteSavedPlayer(_ player: SavedPlayer) throws {
        modelContext.delete(player)
        try modelContext.save()
    }

    /// Renames a `SavedPlayer` in place. Safe to do at any time, including
    /// after the player has appeared in past matches — identity is the
    /// stable `id`, not `name`, so this never breaks historical stats
    /// attribution (see `personalRecord`, Task 5). Exists specifically so
    /// a name collision (e.g. two different people both saved as "Mike")
    /// can be disambiguated — e.g. renaming one to "Mike S." — without
    /// losing anything.
    public func renameSavedPlayer(_ player: SavedPlayer, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        player.name = trimmed
        try modelContext.save()
    }

    /// Clears `isMe` on whichever `SavedPlayer` currently holds it before
    /// setting it on this one, so the exactly-one-"Me" invariant always
    /// holds after this call. Only touches the one previous holder (not
    /// every saved player) — safe because this function is the only writer
    /// of `isMe`, so "at most one `true`" holds by induction.
    public func setMePlayer(_ player: SavedPlayer) throws {
        if let previousMe = try fetchMePlayer(), previousMe.id != player.id {
            previousMe.isMe = false
        }
        player.isMe = true
        try modelContext.save()
    }

    /// Suggestion chips for `MatchSetupView`'s name fields. Empty `query`
    /// returns everyone. Ranking is derived fresh from match history on
    /// every call, not cached — see this plan's Task 1 rationale against
    /// stored counters.
    public func suggestedPlayers(matching query: String) throws -> [SavedPlayer] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let players = try fetchAllSavedPlayers()
        let matches = try fetchMatchHistory()

        // Build stats dictionary once, keyed by player ID. Initialize every player
        // (even those with no matches) to (Date.distantPast, 0), then update from
        // match history. This avoids O(N*M*log(N)) closure calls during sort.
        var statsDict: [UUID: (mostRecent: Date, timesPlayed: Int)] = [:]
        for player in players {
            statsDict[player.id] = (Date.distantPast, 0)
        }
        for match in matches {
            for side in match.teamSides ?? [] {
                for player in side.players ?? [] {
                    if var current = statsDict[player.id] {
                        current.timesPlayed += 1
                        if match.completedAt > current.mostRecent {
                            current.mostRecent = match.completedAt
                        }
                        statsDict[player.id] = current
                    }
                }
            }
        }

        let filtered = trimmedQuery.isEmpty
            ? players
            : players.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }

        return filtered.sorted { lhs, rhs in
            let lhsStats = statsDict[lhs.id] ?? (Date.distantPast, 0)
            let rhsStats = statsDict[rhs.id] ?? (Date.distantPast, 0)
            if lhsStats.mostRecent != rhsStats.mostRecent {
                return lhsStats.mostRecent > rhsStats.mostRecent
            }
            return lhsStats.timesPlayed > rhsStats.timesPlayed
        }
    }

    /// A pure computation over already-fetched match history — no I/O, so
    /// callers that already hold `[MatchRecord]` (e.g. a loaded History
    /// screen) can call this directly without a redundant fetch.
    public func personalRecord(
        for player: SavedPlayer,
        in matches: [MatchRecord]
    ) -> (wins: Int, losses: Int, pointsFor: Int, pointsAgainst: Int) {
        var wins = 0, losses = 0, pointsFor = 0, pointsAgainst = 0
        for match in matches {
            guard let mySide = (match.teamSides ?? []).first(where: { side in
                (side.players ?? []).contains { $0.id == player.id }
            }) else { continue }

            if mySide.team == match.winningTeam {
                wins += 1
            } else {
                losses += 1
            }

            let finalGame = (match.games ?? []).max(by: { $0.gameNumber < $1.gameNumber })
            if let finalGame {
                let myScore = mySide.team == .teamA ? finalGame.teamAFinalScore : finalGame.teamBFinalScore
                let theirScore = mySide.team == .teamA ? finalGame.teamBFinalScore : finalGame.teamAFinalScore
                pointsFor += myScore
                pointsAgainst += theirScore
            }
        }
        return (wins, losses, pointsFor, pointsAgainst)
    }

    /// Deletes every completed match. Cascades to each match's `TeamSide`,
    /// `GameRecord`, and `PointEvent` rows via their `.cascade` delete rules.
    public func deleteAllMatchHistory() throws {
        let existing = try modelContext.fetch(FetchDescriptor<MatchRecord>())
        for record in existing {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}
