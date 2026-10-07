import XCTest
import SwiftData
@testable import PickleballKit

final class PersistenceModelsTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        try ModelContext(PersistenceContainer.makeInMemoryContainer())
    }

    func testMatchRecordWithRelationshipsPersistsAndReloads() throws {
        let context = try makeInMemoryContext()

        let record = MatchRecord(
            startedAt: Date(),
            completedAt: Date(),
            matchFormat: .bestOfThree,
            winningTeam: .teamA,
            configurationData: Data()
        )
        let teamA = TeamSide(team: .teamA, displayName: "The Smashers")
        let teamB = TeamSide(team: .teamB, displayName: "Net Ninjas")
        teamA.match = record
        teamB.match = record
        record.teamSides = [teamA, teamB]

        let game = GameRecord(gameNumber: 1, teamAFinalScore: 11, teamBFinalScore: 7, winningTeam: .teamA)
        game.match = record
        let point = PointEvent(sequenceNumber: 1, scoringTeam: .teamA, teamAScoreAfter: 1, teamBScoreAfter: 0)
        point.game = game
        game.points = [point]
        record.games = [game]

        // Every object is inserted explicitly — this package's established
        // pattern (see MatchRepository.saveCompletedMatch) is to never rely
        // on SwiftData's relationship cascade-insert, which was found to
        // nondeterministically drop rows from a larger nested graph.
        context.insert(record)
        context.insert(teamA)
        context.insert(teamB)
        context.insert(game)
        context.insert(point)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MatchRecord>())
        XCTAssertEqual(fetched.count, 1)
        let reloaded = try XCTUnwrap(fetched.first)
        XCTAssertEqual(reloaded.winningTeam, .teamA)
        XCTAssertEqual(reloaded.teamSides?.count, 2)
        XCTAssertEqual(reloaded.games?.count, 1)
        XCTAssertEqual(reloaded.games?.first?.points?.count, 1)
        XCTAssertEqual(reloaded.games?.first?.points?.first?.scoringTeam, .teamA)
    }
}
