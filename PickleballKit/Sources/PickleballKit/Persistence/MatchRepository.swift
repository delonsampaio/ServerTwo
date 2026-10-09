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
        completedAt: Date = Date()
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
