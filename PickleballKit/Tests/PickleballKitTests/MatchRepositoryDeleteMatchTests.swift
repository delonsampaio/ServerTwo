import XCTest
import SwiftData
@testable import PickleballKit

final class MatchRepositoryDeleteMatchTests: XCTestCase {
    private func makeRepository() throws -> (MatchRepository, ModelContext) {
        let context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        return (MatchRepository(modelContext: context), context)
    }

    private let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

    /// A live-played best-of-1 (11 logged points) so the match owns point events.
    @discardableResult
    private func playedMatch(
        _ repository: MatchRepository,
        winner: Team = .teamA,
        teamA: [SavedPlayer] = [],
        teamB: [SavedPlayer] = [],
        completedAt: Date = Date()
    ) throws -> MatchRecord {
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        playOutGame(match, winner: winner)
        return try repository.saveCompletedMatch(
            match,
            teamAName: TeamNaming.displayName(forPlayerNames: teamA.map(\.name), team: .teamA),
            teamBName: TeamNaming.displayName(forPlayerNames: teamB.map(\.name), team: .teamB),
            startedAt: completedAt.addingTimeInterval(-600),
            completedAt: completedAt,
            teamAPlayers: teamA,
            teamBPlayers: teamB
        )
    }

    private func counts(_ context: ModelContext) throws -> (matches: Int, sides: Int, games: Int, points: Int) {
        (
            try context.fetchCount(FetchDescriptor<MatchRecord>()),
            try context.fetchCount(FetchDescriptor<TeamSide>()),
            try context.fetchCount(FetchDescriptor<GameRecord>()),
            try context.fetchCount(FetchDescriptor<PointEvent>())
        )
    }

    func testDeletingOneOfSeveralLeavesTheOthersUntouched() throws {
        let (repository, context) = try makeRepository()
        let first = try playedMatch(repository, completedAt: Date(timeIntervalSince1970: 1000))
        let second = try playedMatch(repository, completedAt: Date(timeIntervalSince1970: 2000))
        let third = try playedMatch(repository, completedAt: Date(timeIntervalSince1970: 3000))
        let before = try counts(context)
        let perMatchPoints = before.points / 3
        XCTAssertGreaterThan(perMatchPoints, 0)

        try repository.deleteMatch(second)

        let after = try counts(context)
        XCTAssertEqual(after.matches, 2)
        XCTAssertEqual(after.sides, 4)
        XCTAssertEqual(after.games, 2)
        XCTAssertEqual(after.points, before.points - perMatchPoints)
        let remaining = try repository.fetchMatchHistory()
        XCTAssertEqual(Set(remaining.map(\.id)), [first.id, third.id])
        for match in remaining {
            XCTAssertEqual(match.teamSides?.count, 2)
            XCTAssertEqual(match.games?.count, 1)
            XCTAssertEqual(match.games?.first?.points?.count, perMatchPoints)
        }
    }

    func testTheDeletedMatchLeavesNoOrphanedSidesGamesOrPoints() throws {
        let (repository, context) = try makeRepository()
        let match = try playedMatch(repository)
        let before = try counts(context)
        XCTAssertEqual(before.matches, 1)
        XCTAssertEqual(before.sides, 2)
        XCTAssertEqual(before.games, 1)
        XCTAssertGreaterThan(before.points, 0)

        try repository.deleteMatch(match)

        let after = try counts(context)
        XCTAssertEqual(after.matches, 0)
        XCTAssertEqual(after.sides, 0)
        XCTAssertEqual(after.games, 0)
        XCTAssertEqual(after.points, 0)
    }

    func testSavedPlayersAndMeSurviveTheDeletion() throws {
        let (repository, _) = try makeRepository()
        let me = try XCTUnwrap(repository.upsertSavedPlayer(name: "Me"))
        try repository.setMePlayer(me)
        let bob = try XCTUnwrap(repository.upsertSavedPlayer(name: "Bob"))
        let match = try playedMatch(repository, teamA: [me], teamB: [bob])

        try repository.deleteMatch(match)

        XCTAssertEqual(Set(try repository.fetchAllSavedPlayers().map(\.name)), ["Me", "Bob"])
        XCTAssertEqual(try repository.fetchMePlayer()?.id, me.id)
        XCTAssertTrue((me.teamSides ?? []).isEmpty)
    }

    func testRecordStreakAndChemistryExcludeTheDeletedMatch() throws {
        let (repository, _) = try makeRepository()
        let me = try XCTUnwrap(repository.upsertSavedPlayer(name: "Me"))
        try repository.setMePlayer(me)
        let bob = try XCTUnwrap(repository.upsertSavedPlayer(name: "Bob"))
        try playedMatch(repository, winner: .teamB, teamA: [me], teamB: [bob], completedAt: Date(timeIntervalSince1970: 1000)) // loss
        try playedMatch(repository, winner: .teamA, teamA: [me], teamB: [bob], completedAt: Date(timeIntervalSince1970: 2000)) // win
        let latest = try playedMatch(repository, winner: .teamA, teamA: [me], teamB: [bob], completedAt: Date(timeIntervalSince1970: 3000)) // win

        var history = try repository.fetchMatchHistory()
        XCTAssertEqual(repository.personalRecord(for: me, in: history).wins, 2)
        XCTAssertEqual(repository.winStreak(for: me, in: history), 2)
        XCTAssertEqual(repository.chemistry(between: me, and: bob, in: history).asOpponent?.wins, 2)

        try repository.deleteMatch(latest)

        history = try repository.fetchMatchHistory()
        let record = repository.personalRecord(for: me, in: history)
        XCTAssertEqual(record.wins, 1)
        XCTAssertEqual(record.losses, 1)
        XCTAssertEqual(repository.winStreak(for: me, in: history), 1)
        let opponent = try XCTUnwrap(repository.chemistry(between: me, and: bob, in: history).asOpponent)
        XCTAssertEqual(opponent.wins, 1)
        XCTAssertEqual(opponent.losses, 1)
    }

    func testDeletingTheOnlyMatchLeavesAnEmptyHistory() throws {
        let (repository, _) = try makeRepository()
        let match = try repository.saveQuickLoggedMatch(
            configuration: config, matchFormat: .bestOfOne,
            teamAName: "A", teamBName: "B", gameScores: [(11, 7)]
        )

        try repository.deleteMatch(match)

        XCTAssertTrue(try repository.fetchMatchHistory().isEmpty)
    }

    func testDeletingAQuickLoggedMatchWithNoPointsRemovesItsGamesAndSides() throws {
        let (repository, context) = try makeRepository()
        let keep = try repository.saveQuickLoggedMatch(
            configuration: config, matchFormat: .bestOfOne,
            teamAName: "A", teamBName: "B", gameScores: [(11, 7)]
        )
        let duplicate = try repository.saveQuickLoggedMatch(
            configuration: config, matchFormat: .bestOfOne,
            teamAName: "A", teamBName: "B", gameScores: [(11, 7)]
        )

        try repository.deleteMatch(duplicate)

        let after = try counts(context)
        XCTAssertEqual(after.matches, 1)
        XCTAssertEqual(after.sides, 2)
        XCTAssertEqual(after.games, 1)
        XCTAssertEqual(try repository.fetchMatchHistory().map(\.id), [keep.id])
    }

    func testAFailedSaveRollsBackAndLeavesTheMatchIntact() throws {
        let (repository, context) = try makeRepository()
        let match = try playedMatch(repository)
        let before = try counts(context)
        struct Boom: Error {}

        XCTAssertThrowsError(try repository.deleteMatch(match, beforeSave: { throw Boom() })) {
            XCTAssertTrue($0 is Boom)
        }

        let after = try counts(context)
        XCTAssertEqual(after.matches, before.matches)
        XCTAssertEqual(after.sides, before.sides)
        XCTAssertEqual(after.games, before.games)
        XCTAssertEqual(after.points, before.points)
        XCTAssertEqual(try repository.fetchMatchHistory().map(\.id), [match.id])
    }
}
