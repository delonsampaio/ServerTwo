import Foundation
import SwiftData

/// Why a payload was refused. The phone acknowledges a rejected match anyway
/// (a permanently malformed record must not be resent forever), so the reason
/// is for tests and logs, not for the user.
public enum SyncedMatchRejection: String, Error, Sendable, Equatable {
    case invalidSchemaVersion
    case undecodablePayload
    case idMismatch
    case invalidMatchFormat
    case invalidConfiguration
    case invalidWinner
    case invalidGameCount
    case invalidGameNumbers
    case invalidGameScore
    case gameAfterMatchDecided
    case winnerMismatch
    case invalidPoints
    case invalidDate
}

public enum ImportResult: Sendable, Equatable {
    case imported
    /// Already here (by id) or already seen (imported then deleted); nothing changed.
    case duplicate
    case rejected(SyncedMatchRejection)
    /// From a newer app version: not acknowledged, retried after the phone updates.
    case unsupportedNewerSchema
}

/// A payload that passed validation, with every free-text and date field
/// already cleaned, so the insert below cannot be handed anything unchecked.
struct ValidatedSyncedMatch {
    struct Point {
        let sequenceNumber: Int
        let scoringTeam: Team
        let teamAScoreAfter: Int
        let teamBScoreAfter: Int
    }

    struct Game {
        let number: Int
        let teamAFinalScore: Int
        let teamBFinalScore: Int
        let winningTeam: Team
        let completedAt: Date?
        let points: [Point]
    }

    let id: UUID
    let startedAt: Date
    let completedAt: Date
    let matchFormat: MatchFormat
    let winningTeam: Team
    let configurationData: Data
    let teamAName: String
    let teamBName: String
    /// Cleaned and capped to the play mode (empty for an old payload).
    let teamAPlayers: [SyncedPlayerRef]
    let teamBPlayers: [SyncedPlayerRef]
    let games: [Game]
}

enum SyncedMatchValidator {
    static let maxNameLength = 64
    static let maxScore = 99
    static let maxPointsPerGame = 500
    static let maxTimeouts = 10

    static func validate(_ payload: SyncedMatchPayload) -> Result<ValidatedSyncedMatch, SyncedMatchRejection> {
        guard payload.schemaVersion >= 1 else { return .failure(.invalidSchemaVersion) }
        guard let format = MatchFormat(rawValue: payload.matchFormatRawValue) else {
            return .failure(.invalidMatchFormat)
        }
        guard let configuration = try? JSONDecoder().decode(GameConfiguration.self, from: payload.configurationData),
              (0...maxTimeouts).contains(configuration.timeoutsPerTeam) else {
            return .failure(.invalidConfiguration)
        }
        guard let winner = Team(rawValue: payload.winningTeamRawValue) else { return .failure(.invalidWinner) }

        // Dates: finite, and the start is never after the finish.
        guard payload.startedAt.timeIntervalSinceReferenceDate.isFinite,
              payload.completedAt.timeIntervalSinceReferenceDate.isFinite else {
            return .failure(.invalidDate)
        }
        let startedAt = min(payload.startedAt, payload.completedAt)

        let games = payload.games.sorted { $0.number < $1.number }
        guard (1...(2 * format.gamesToWin - 1)).contains(games.count) else { return .failure(.invalidGameCount) }
        guard games.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 }) else {
            return .failure(.invalidGameNumbers)
        }

        var gamesWon: [Team: Int] = [.teamA: 0, .teamB: 0]
        var validated: [ValidatedSyncedMatch.Game] = []
        for game in games {
            // Same rule as Quick Log: nothing may follow the deciding game.
            guard gamesWon[.teamA, default: 0] < format.gamesToWin,
                  gamesWon[.teamB, default: 0] < format.gamesToWin else {
                return .failure(.gameAfterMatchDecided)
            }
            guard (0...maxScore).contains(game.teamAFinalScore), (0...maxScore).contains(game.teamBFinalScore),
                  configuration.isCompletedGameScore(teamA: game.teamAFinalScore, teamB: game.teamBFinalScore),
                  let gameWinner = Team(rawValue: game.winningTeamRawValue),
                  gameWinner == (game.teamAFinalScore > game.teamBFinalScore ? Team.teamA : Team.teamB) else {
                return .failure(.invalidGameScore)
            }
            gamesWon[gameWinner, default: 0] += 1

            guard let points = validatePoints(game) else { return .failure(.invalidPoints) }

            var completedAt = game.completedAt
            if let date = completedAt {
                // A missing or out-of-range time is just unknown, not fatal.
                if !date.timeIntervalSinceReferenceDate.isFinite || date < startedAt || date > payload.completedAt {
                    completedAt = nil
                }
            }
            validated.append(.init(
                number: game.number,
                teamAFinalScore: game.teamAFinalScore,
                teamBFinalScore: game.teamBFinalScore,
                winningTeam: gameWinner,
                completedAt: completedAt,
                points: points
            ))
        }

        let playersPerSide = WatchMatchPlayers.maxPlayersPerSide(for: configuration.playMode)
        let derivedWinner: Team? = gamesWon[.teamA, default: 0] >= format.gamesToWin ? .teamA
            : gamesWon[.teamB, default: 0] >= format.gamesToWin ? .teamB : nil
        guard derivedWinner == winner else { return .failure(.winnerMismatch) }

        return .success(ValidatedSyncedMatch(
            id: payload.id,
            startedAt: startedAt,
            completedAt: payload.completedAt,
            matchFormat: format,
            winningTeam: winner,
            configurationData: payload.configurationData,
            teamAName: sanitizedName(payload.teamAName, team: .teamA),
            teamBName: sanitizedName(payload.teamBName, team: .teamB),
            teamAPlayers: validatedPlayers(payload.teamAPlayers, limit: playersPerSide),
            teamBPlayers: validatedPlayers(payload.teamBPlayers, limit: playersPerSide),
            games: validated
        ))
    }

    /// Deliberately no stricter than the engine: a manual score correction can
    /// make the derived log skip scores, so it only requires an ordered log
    /// whose scores never go down, stay in range and end on the game's final
    /// score. (Watch matches have no corrections, but the format is shared.)
    private static func validatePoints(_ game: SyncedMatchPayload.Game) -> [ValidatedSyncedMatch.Point]? {
        guard game.points.count <= maxPointsPerGame else { return nil }
        let points = game.points.sorted { $0.sequenceNumber < $1.sequenceNumber }
        var previousA = 0, previousB = 0
        var result: [ValidatedSyncedMatch.Point] = []
        for (index, point) in points.enumerated() {
            guard point.sequenceNumber == index + 1,
                  let team = Team(rawValue: point.scoringTeamRawValue),
                  (0...maxScore).contains(point.teamAScoreAfter), (0...maxScore).contains(point.teamBScoreAfter),
                  point.teamAScoreAfter >= previousA, point.teamBScoreAfter >= previousB else { return nil }
            previousA = point.teamAScoreAfter
            previousB = point.teamBScoreAfter
            result.append(.init(
                sequenceNumber: point.sequenceNumber,
                scoringTeam: team,
                teamAScoreAfter: point.teamAScoreAfter,
                teamBScoreAfter: point.teamBScoreAfter
            ))
        }
        if let last = result.last,
           last.teamAScoreAfter != game.teamAFinalScore || last.teamBScoreAfter != game.teamBFinalScore {
            return nil
        }
        return result
    }

    /// Player entries are checked like the other payload text (control
    /// characters removed, trimmed, non-blank, at most `maxNameLength`); an
    /// invalid entry is dropped, not repaired, and the match still imports
    /// (its name strings remain). At most `limit` entries survive: one a side
    /// for singles, two for doubles, decided by the payload's configuration.
    static func validatedPlayers(_ entries: [SyncedPlayerRef]?, limit: Int) -> [SyncedPlayerRef] {
        var result: [SyncedPlayerRef] = []
        for entry in entries ?? [] {
            guard let name = PlayerNameRules.validated(entry.name) else { continue }
            result.append(SyncedPlayerRef(savedPlayerID: entry.savedPlayerID, name: name))
            if result.count == limit { break }
        }
        return result
    }

    /// Trimmed, control characters (including newlines) removed, capped, and a
    /// blank result becomes the placeholder; the placeholder itself passes
    /// through unchanged, which is what keeps "Team A"/"Team B" matches blank
    /// for Edit Players and Rematch.
    static func sanitizedName(_ name: String, team: Team) -> String {
        let cleaned = String(String.UnicodeScalarView(
            name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        ))
        let capped = String(cleaned.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        return TeamNaming.resolvedName(capped.trimmingCharacters(in: .whitespacesAndNewlines), team: team)
    }
}

extension MatchRepository {
    /// The saved match with this id, if any.
    public func fetchMatchRecord(id: UUID) throws -> MatchRecord? {
        var descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// The saved match that started at exactly this instant, if any (a match and
    /// its in-progress snapshot share their start time).
    public func fetchMatchRecord(startedAt: Date) throws -> MatchRecord? {
        var descriptor = FetchDescriptor<MatchRecord>(predicate: #Predicate { $0.startedAt == startedAt })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Stores a match the Watch finished. Idempotent and first-write-wins: a
    /// match already here (by id) or already seen (imported, then deleted)
    /// changes nothing, so an edited match is never overwritten and a deleted
    /// one never comes back. Never touches the in-progress snapshot (unlike
    /// `saveCompletedMatch`): a live phone match must not lose its crash
    /// recovery because a Watch match arrived.
    ///
    /// Players: a payload from a Watch that chose players carries entries per
    /// side; each is linked to a saved player here (see `resolveSyncedPlayer`),
    /// and a name the phone has never seen becomes a new saved player, exactly
    /// like a name typed in match setup. A payload without entries (an older
    /// Watch, or no players chosen) imports its display names only, unlinked.
    ///
    /// One `save()` commits the match AND any new players together, so nothing
    /// is half-imported (this never calls `upsertSavedPlayer`, which saves on
    /// its own). On failure `rollback()` discards the inserted graph, new
    /// players included (all inserts, so no staged delete can make it trap),
    /// and the error is thrown, which the caller treats as "do not
    /// acknowledge, try again later".
    public func importSyncedMatch(_ payload: SyncedMatchPayload) throws -> ImportResult {
        try importSyncedMatch(payload, beforeSave: nil)
    }

    /// `beforeSave` is a test seam: it runs after everything is inserted and
    /// before the single `save()`, so a test can make that step fail.
    func importSyncedMatch(_ payload: SyncedMatchPayload, beforeSave: (() throws -> Void)?) throws -> ImportResult {
        guard payload.schemaVersion <= SyncedMatchPayload.currentSchemaVersion else {
            return .unsupportedNewerSchema
        }
        if seenMatchIDs.contains(payload.id) { return .duplicate }
        if try fetchMatchRecord(id: payload.id) != nil { return .duplicate }

        let match: ValidatedSyncedMatch
        switch SyncedMatchValidator.validate(payload) {
        case .failure(let reason): return .rejected(reason)
        case .success(let validated): match = validated
        }

        do {
            let record = MatchRecord(
                id: match.id,
                startedAt: match.startedAt,
                completedAt: match.completedAt,
                matchFormat: match.matchFormat,
                winningTeam: match.winningTeam,
                configurationData: match.configurationData
            )
            // Every object inserted explicitly, as `saveCompletedMatch` does
            // (cascade-insert through relationships is unreliable for graphs
            // this size).
            modelContext.insert(record)

            let teamASide = TeamSide(team: .teamA, displayName: match.teamAName)
            let teamBSide = TeamSide(team: .teamB, displayName: match.teamBName)
            teamASide.match = record
            teamBSide.match = record
            record.teamSides = [teamASide, teamBSide]
            modelContext.insert(teamASide)
            modelContext.insert(teamBSide)

            if !match.teamAPlayers.isEmpty || !match.teamBPlayers.isEmpty {
                try linkSyncedPlayers(match, teamASide: teamASide, teamBSide: teamBSide)
            }

            var gameRecords: [GameRecord] = []
            for game in match.games {
                let gameRecord = GameRecord(
                    gameNumber: game.number,
                    teamAFinalScore: game.teamAFinalScore,
                    teamBFinalScore: game.teamBFinalScore,
                    winningTeam: game.winningTeam
                )
                gameRecord.match = record
                gameRecord.completedAt = game.completedAt
                modelContext.insert(gameRecord)
                gameRecord.points = game.points.map { point in
                    let event = PointEvent(
                        sequenceNumber: point.sequenceNumber,
                        scoringTeam: point.scoringTeam,
                        teamAScoreAfter: point.teamAScoreAfter,
                        teamBScoreAfter: point.teamBScoreAfter
                    )
                    event.game = gameRecord
                    modelContext.insert(event)
                    return event
                }
                gameRecords.append(gameRecord)
            }
            record.games = gameRecords
            try beforeSave?()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        seenMatchIDs.insert(payload.id)
        return .imported
    }

    /// Links the entries of a validated payload to saved players and renames
    /// each side after them, all unsaved (the import's one `save()` commits).
    /// One fetch of all saved players is the working list: a new player is
    /// inserted and appended to it, so two slots with the same new name share
    /// one player. A player is linked at most once per match: a repeat, on the
    /// same side or the other, is dropped (the second side loses it).
    private func linkSyncedPlayers(
        _ match: ValidatedSyncedMatch,
        teamASide: TeamSide,
        teamBSide: TeamSide
    ) throws {
        var working = try fetchAllSavedPlayers()
        var used = Set<ObjectIdentifier>()
        func link(_ entries: [SyncedPlayerRef]) -> [SavedPlayer] {
            var linked: [SavedPlayer] = []
            for entry in entries {
                let player = resolveSyncedPlayer(entry, working: &working)
                if used.insert(ObjectIdentifier(player)).inserted { linked.append(player) }
            }
            return linked
        }
        let playersA = link(match.teamAPlayers)
        let playersB = link(match.teamBPlayers)
        // A side whose entries all resolved to nobody keeps the payload's
        // name; otherwise the name is rebuilt from the linked players, as
        // `updateSides` does (a renamed saved player shows its current name).
        if !playersA.isEmpty {
            teamASide.players = playersA
            teamASide.displayName = TeamNaming.displayName(forPlayerNames: playersA.map(\.name), team: .teamA)
        }
        if !playersB.isEmpty {
            teamBSide.players = playersB
            teamBSide.displayName = TeamNaming.displayName(forPlayerNames: playersB.map(\.name), team: .teamB)
        }
    }

    /// A known id is trusted, even if the player was renamed since the Watch
    /// last heard (the Watch cannot edit a picked name, and matching the old
    /// name could attach the wrong "Mike"). A missing or unknown id falls back
    /// to a case-insensitive name match, then to a new player: inserted
    /// WITHOUT saving, so the caller's rollback can still discard it.
    private func resolveSyncedPlayer(_ entry: SyncedPlayerRef, working: inout [SavedPlayer]) -> SavedPlayer {
        if let id = entry.savedPlayerID, let known = working.first(where: { $0.id == id }) { return known }
        if let named = working.first(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) {
            return named
        }
        let player = SavedPlayer(name: entry.name)
        modelContext.insert(player)
        working.append(player)
        return player
    }
}
