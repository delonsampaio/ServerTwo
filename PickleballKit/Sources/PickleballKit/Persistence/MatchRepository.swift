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

    /// Deterministic even if more than one row has `isMe == true` — e.g.
    /// transiently, between a CloudKit sync and the next `setMePlayer`
    /// call that self-heals it. Ties break by `id` so two reads of the
    /// same (even if momentarily inconsistent) data always agree.
    public func fetchMePlayer() throws -> SavedPlayer? {
        try fetchAllSavedPlayers()
            .filter { $0.isMe }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first
    }

    /// Re-resolves `SavedPlayer`s by id in THIS repository's own context,
    /// silently dropping any id that no longer resolves (e.g. the player
    /// was deleted from Manage Players while a match was in progress).
    /// Exists so `ActiveMatchController` never carries a `SavedPlayer`
    /// object across a `ModelContext` boundary — see the final
    /// whole-branch review, Critical #1/#2.
    public func fetchSavedPlayers(ids: [UUID]) throws -> [SavedPlayer] {
        guard !ids.isEmpty else { return [] }
        // `uniquingKeysWith:`, not `uniqueKeysWithValues:` — `id` carries no
        // `@Attribute(.unique)` (this store is CloudKit-synced, where a
        // uniqueness constraint can't be enforced across devices), so two
        // rows sharing an id is exactly the kind of transient divergence
        // this method exists to tolerate. `uniqueKeysWithValues:` would
        // trap on that instead of degrading gracefully.
        let byID = Dictionary(try fetchAllSavedPlayers().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// Finds-or-creates a `SavedPlayer` by trimmed, case-INSENSITIVE name
    /// match (typing "mike" must find the existing "Mike" — otherwise a
    /// lowercase habit silently creates a second identity and, worst
    /// case, a match never counts toward "Your Record" if the real "Me"
    /// player was the one typed in the wrong case). The first-saved
    /// casing is canonical; later upserts that only differ by case reuse
    /// the existing row's `name` as-is. Different real people who happen
    /// to share a name are a separate, accepted non-goal (see spec §3) —
    /// this only collapses case variants of what is meant to be the same
    /// string. Returns `nil` for blank/whitespace-only input without
    /// creating anything — callers must never upsert an empty field.
    @discardableResult
    public func upsertSavedPlayer(name: String) throws -> SavedPlayer? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = try fetchAllSavedPlayers().first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
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

    /// Clears `isMe` on every `SavedPlayer` that currently has it (not
    /// just the one `fetchMePlayer()` would return) before setting it on
    /// this one. The store is CloudKit-synced, so two devices can each
    /// independently mark a different player "Me" while offline; clearing
    /// every holder here — rather than trusting "at most one `true`"
    /// as an invariant maintained purely by this function being the only
    /// writer — makes the next call on either device self-heal the store
    /// back to exactly one, instead of compounding the divergence.
    public func setMePlayer(_ player: SavedPlayer) throws {
        for other in try fetchAllSavedPlayers() where other.isMe && other.id != player.id {
            other.isMe = false
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
            if lhsStats.timesPlayed != rhsStats.timesPlayed {
                return lhsStats.timesPlayed > rhsStats.timesPlayed
            }
            // Final tiebreak so players with identical (never-played)
            // stats don't reshuffle between keystrokes — `sorted` is not
            // guaranteed stable.
            return lhs.name < rhs.name
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

            // Sum every game in the match, not just the deciding one — a
            // best-of-3 that went 2-1 counts all three games' points, not
            // only the last one played. (The previous "final game only"
            // version silently dropped 2/3 of a best-of-3's points under a
            // label still claiming to be "Points For/Against" — found in
            // the final whole-branch review, Important #3.)
            for game in match.games ?? [] {
                let myScore = mySide.team == .teamA ? game.teamAFinalScore : game.teamBFinalScore
                let theirScore = mySide.team == .teamA ? game.teamBFinalScore : game.teamAFinalScore
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
