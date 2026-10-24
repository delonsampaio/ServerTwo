import SwiftData
import Foundation

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public enum MatchRepositoryError: Error, Equatable {
    case matchNotOver
    case invalidGameScore
    /// The same player (by saved identity or by case-insensitive name) was
    /// entered twice in one match. Carries the name as typed.
    case duplicatePlayer(String)
    case tooManyPlayers
    case missingTeamSide
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

    /// Persists a finished `PickleballMatch` as history: a `MatchRecord`
    /// plus its `TeamSide`/`GameRecord`/`PointEvent` graph. `gameCompletionDates`
    /// is never computed here — it's captured live, point by point, by
    /// `ActiveMatchController.syncGameCompletionDates()` and simply handed
    /// through to populate each `GameRecord.completedAt`; this method has no
    /// other source of those timestamps (a crash-resumed game's date is
    /// `nil` for the same reason — see `GameRecord.completedAt`'s doc comment).
    @discardableResult
    public func saveCompletedMatch(
        _ match: PickleballMatch,
        teamAName: String,
        teamBName: String,
        startedAt: Date,
        completedAt: Date = Date(),
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = [],
        gameCompletionDates: [Date?] = []
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
            // `gameWinner` is nil only for a game decided at a score the strict
            // completed-score rule no longer recognises (a legacy in-progress
            // snapshot). Fall back to the higher score rather than silently
            // dropping the game — it is already counted in `gamesWon`.
            let gameWinner = game.gameWinner
                ?? (game.state.teamAScore > game.state.teamBScore ? Team.teamA : Team.teamB)
            gameNumber += 1
            let gameRecord = GameRecord(
                gameNumber: gameNumber,
                teamAFinalScore: game.state.teamAScore,
                teamBFinalScore: game.state.teamBScore,
                winningTeam: gameWinner
            )
            gameRecord.match = record
            gameRecord.completedAt = gameCompletionDates[safe: gameNumber - 1].flatMap { $0 }
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

    /// A match recorded after the fact from final scores alone, with no
    /// point-by-point log — bypasses `PickleballMatch` entirely since there's
    /// no live match to drive. Each entry in `gameScores` must be a legal
    /// completed game per `configuration.isCompletedGameScore`, and no entry
    /// may follow the game that decides the match. Throws `.invalidGameScore`
    /// for either violation and `.matchNotOver` if the entries don't yet
    /// give one team `matchFormat.gamesToWin` games.
    @discardableResult
    public func saveQuickLoggedMatch(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        teamAName: String,
        teamBName: String,
        gameScores: [(teamA: Int, teamB: Int)],
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = [],
        completedAt: Date = Date()
    ) throws -> MatchRecord {
        var gamesWon: [Team: Int] = [.teamA: 0, .teamB: 0]
        var gameRecords: [GameRecord] = []
        for (index, score) in gameScores.enumerated() {
            // A game entry after the match was already decided (e.g. a 3rd
            // game for a Best of 3 that's already 2-0) is as invalid as a
            // bad score — without this, extra trailing entries would
            // silently inflate gamesWon past matchFormat.gamesToWin and
            // still "succeed."
            guard gamesWon[.teamA, default: 0] < matchFormat.gamesToWin,
                  gamesWon[.teamB, default: 0] < matchFormat.gamesToWin else {
                throw MatchRepositoryError.invalidGameScore
            }
            guard configuration.isCompletedGameScore(teamA: score.teamA, teamB: score.teamB) else {
                throw MatchRepositoryError.invalidGameScore
            }
            let winner: Team = score.teamA > score.teamB ? .teamA : .teamB
            gamesWon[winner, default: 0] += 1
            // points and completedAt are left at their defaults (empty, nil):
            // a quick-logged game has no point log and no live timing data.
            gameRecords.append(GameRecord(
                gameNumber: index + 1,
                teamAFinalScore: score.teamA,
                teamBFinalScore: score.teamB,
                winningTeam: winner
            ))
        }
        guard let matchWinner = (
            gamesWon[.teamA, default: 0] >= matchFormat.gamesToWin ? Team.teamA :
            gamesWon[.teamB, default: 0] >= matchFormat.gamesToWin ? Team.teamB : nil
        ) else {
            throw MatchRepositoryError.matchNotOver
        }

        let configurationData = try JSONEncoder().encode(configuration)
        let record = MatchRecord(
            startedAt: completedAt,
            completedAt: completedAt,
            matchFormat: matchFormat,
            winningTeam: matchWinner,
            configurationData: configurationData
        )
        // Same explicit-insert-for-every-object discipline as
        // saveCompletedMatch, for the same reason (see its own comment).
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

        for gameRecord in gameRecords {
            gameRecord.match = record
            modelContext.insert(gameRecord)
        }
        record.games = gameRecords

        try modelContext.save()

        return record
    }

    /// Replaces the players of a completed match's two sides — fixes a wrong
    /// pick or fills a blank left at save time. Blank entries are dropped.
    /// Names resolve like match setup does (a still-valid picked id wins,
    /// otherwise `upsertSavedPlayer`, so a typed name links the existing
    /// player instead of duplicating it). The same player twice anywhere in
    /// the match throws `.duplicatePlayer` and a side with more than two
    /// players throws `.tooManyPlayers`; both are checked BEFORE anything is
    /// created or changed, so a rejected edit leaves no stray saved players.
    /// Only `players` and `displayName` change: scores, winner, rules,
    /// games and the point log are untouched, and every stat derives from
    /// the linked players, so it follows on its own.
    public func updateSides(
        of match: MatchRecord,
        teamA: [PlayerSlotEntry],
        teamB: [PlayerSlotEntry]
    ) throws {
        guard let sideA = (match.teamSides ?? []).first(where: { $0.team == .teamA }),
              let sideB = (match.teamSides ?? []).first(where: { $0.team == .teamB }) else {
            throw MatchRepositoryError.missingTeamSide
        }
        let entriesA = teamA.filter { !$0.isBlank }
        let entriesB = teamB.filter { !$0.isBlank }
        guard entriesA.count <= 2, entriesB.count <= 2 else {
            throw MatchRepositoryError.tooManyPlayers
        }

        let existing = try fetchAllSavedPlayers()
        if let duplicate = PlayerSlotEntry.firstDuplicateName(in: entriesA + entriesB, among: existing) {
            throw MatchRepositoryError.duplicatePlayer(duplicate)
        }

        do {
            let playersA = try entriesA.compactMap { try resolvePlayer($0, among: existing) }
            let playersB = try entriesB.compactMap { try resolvePlayer($0, among: existing) }
            sideA.players = playersA
            sideB.players = playersB
            sideA.displayName = TeamNaming.displayName(forPlayerNames: playersA.map(\.name), team: .teamA)
            sideB.displayName = TeamNaming.displayName(forPlayerNames: playersB.map(\.name), team: .teamB)
            try modelContext.save()
        } catch {
            // Don't leave half-applied side edits pending in the context.
            modelContext.rollback()
            throw error
        }
    }

    private func resolvePlayer(_ entry: PlayerSlotEntry, among players: [SavedPlayer]) throws -> SavedPlayer? {
        if let player = entry.matchingPlayer(among: players) { return player }
        return try upsertSavedPlayer(name: entry.name)
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

    /// Sets or clears a player's photo. Callers are expected to have already
    /// resized/compressed `data` (see `PlayerPhotoProcessor`) — this method
    /// just stores whatever it's given. `data: nil` removes the photo,
    /// reverting that player to the initials fallback everywhere it's shown.
    public func setPlayerPhoto(_ player: SavedPlayer, data: Data?) throws {
        player.photoData = data
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

    /// Which side `player` was on in `match`, if any. Matches saved before
    /// a side's players were linked (or any save path that skipped linking
    /// them) have `side.players == nil` — an id match alone would silently
    /// skip those matches out of every stat below, even when the player
    /// obviously appears in the side's own display name. Falling back to
    /// an exact match against the side's `" & "`-joined name components
    /// (not a raw substring test, so "Delon" won't accidentally match
    /// inside some other "Delonte") recovers those matches instead of
    /// quietly undercounting them.
    private func mySide(for player: SavedPlayer, in match: MatchRecord) -> TeamSide? {
        (match.teamSides ?? []).first { side in
            if let players = side.players, !players.isEmpty {
                return players.contains { $0.id == player.id }
            }
            // A side with nobody entered is named "Team A"/"Team B" — a
            // placeholder, not a player, so it must never match a saved
            // player who happens to be called that.
            guard side.displayName != TeamNaming.placeholderName(for: side.team) else { return false }
            return side.displayName.components(separatedBy: " & ").contains {
                $0.caseInsensitiveCompare(player.name) == .orderedSame
            }
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
            guard let mySide = mySide(for: player, in: match) else { continue }

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

    /// Consecutive wins for `player`, counting backward from the most
    /// recent match they appear in and stopping at the first loss. `matches`
    /// must already be sorted most-recent-first, as `fetchMatchHistory()`
    /// returns them — a pure computation over already-fetched data, same as
    /// `personalRecord`.
    public func winStreak(for player: SavedPlayer, in matches: [MatchRecord]) -> Int {
        var streak = 0
        for match in matches {
            guard let mySide = mySide(for: player, in: match) else { continue }
            guard mySide.team == match.winningTeam else { break }
            streak += 1
        }
        return streak
    }

    /// `player`'s most-recent-first win/loss results, capped at `limit`
    /// matches (fewer if they haven't played that many). `true` = win.
    /// `matches` must already be sorted most-recent-first.
    public func recentForm(for player: SavedPlayer, in matches: [MatchRecord], limit: Int = 5) -> [Bool] {
        var results: [Bool] = []
        for match in matches {
            guard results.count < limit else { break }
            guard let mySide = mySide(for: player, in: match) else { continue }
            results.append(mySide.team == match.winningTeam)
        }
        return results
    }

    /// Whether `player` won `match`, or `nil` if they didn't appear in it
    /// (by either id-linked players or a name-component fallback — see
    /// `mySide(for:in:)`). A pure computation, same as `personalRecord`.
    public func myResult(for player: SavedPlayer, in match: MatchRecord) -> Bool? {
        mySide(for: player, in: match).map { $0.team == match.winningTeam }
    }

    /// `me`'s record against `other`, split by relationship. Each side is
    /// `nil` if `me` and `other` never shared that relationship (e.g. two
    /// players who have only ever partnered have a `nil` asOpponent, not a
    /// 0-0 one) — a relationship that never happened isn't a stat, it's
    /// nothing to report.
    public func chemistry(
        between me: SavedPlayer,
        and other: SavedPlayer,
        in matches: [MatchRecord]
    ) -> (asPartner: (wins: Int, losses: Int)?, asOpponent: (wins: Int, losses: Int)?) {
        // A caller passing the same player for both arguments isn't a real
        // relationship — without this guard every one of their matches would
        // count as a win/loss "with/against themselves."
        guard me.id != other.id else { return (nil, nil) }

        var partnerWins = 0, partnerLosses = 0
        var opponentWins = 0, opponentLosses = 0
        var hasPartnerMatch = false, hasOpponentMatch = false

        for match in matches {
            // Named `meSide`, not `mySide`, so it doesn't shadow the
            // `mySide(for:in:)` method for the rest of this `guard let`
            // chain (and everything below it in this loop) — a prior
            // version named it `mySide` and that shadowing broke the build.
            guard let meSide = mySide(for: me, in: match),
                  let otherSide = mySide(for: other, in: match) else { continue }

            let won = meSide.team == match.winningTeam
            if meSide.team == otherSide.team {
                hasPartnerMatch = true
                won ? (partnerWins += 1) : (partnerLosses += 1)
            } else {
                hasOpponentMatch = true
                won ? (opponentWins += 1) : (opponentLosses += 1)
            }
        }

        return (
            hasPartnerMatch ? (partnerWins, partnerLosses) : nil,
            hasOpponentMatch ? (opponentWins, opponentLosses) : nil
        )
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

    /// Deletes every saved player, including whichever one is "Me". Exists
    /// for a genuine full-reset (e.g. `-UITest-ResetState`) — `SavedPlayer`
    /// rows outlive `deleteAllMatchHistory()`, since the two are otherwise
    /// independent, so a caller that wants a truly clean slate needs both.
    public func deleteAllSavedPlayers() throws {
        let existing = try fetchAllSavedPlayers()
        for player in existing {
            modelContext.delete(player)
        }
        try modelContext.save()
    }
}
