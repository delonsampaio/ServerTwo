import XCTest
import SwiftData
@testable import PickleballKit

final class MatchRepositoryHistoryTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    func testSaveCompletedMatchPersistsFullGraph() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        let saved = try repository.saveCompletedMatch(match, teamAName: "The Smashers", teamBName: "Net Ninjas", startedAt: Date())

        XCTAssertEqual(saved.winningTeam, .teamA)
        XCTAssertEqual(saved.teamSides?.count, 2)
        XCTAssertEqual(saved.games?.count, 1)
        // Relationship arrays have no guaranteed order — orderedPoints
        // sorts by sequenceNumber explicitly.
        let points = try XCTUnwrap(saved.games?.first).orderedPoints
        XCTAssertEqual(points.count, 11)
        XCTAssertEqual(points.last?.teamAScoreAfter, 11)
    }

    func testSaveCompletedMatchThrowsIfMatchIsNotOver() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        match.recordPoint(for: .teamA)

        XCTAssertThrowsError(try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())) { error in
            XCTAssertEqual(error as? MatchRepositoryError, .matchNotOver)
        }
    }

    func testFetchMatchHistoryReturnsNewestFirst() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let earlierMatch = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { earlierMatch.recordPoint(for: .teamA) }
        _ = try repository.saveCompletedMatch(earlierMatch, teamAName: "A", teamBName: "B", startedAt: Date(timeIntervalSince1970: 1000), completedAt: Date(timeIntervalSince1970: 2000))

        let laterMatch = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamB, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { laterMatch.recordPoint(for: .teamB) }
        _ = try repository.saveCompletedMatch(laterMatch, teamAName: "A", teamBName: "B", startedAt: Date(timeIntervalSince1970: 3000), completedAt: Date(timeIntervalSince1970: 4000))

        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.winningTeam, .teamB)
        XCTAssertEqual(history.last?.winningTeam, .teamA)
    }
}
