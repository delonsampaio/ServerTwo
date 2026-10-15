import XCTest
import SwiftData
@testable import PickleballKit

final class MatchRepositoryQuickLogTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    func testSavesABestOfOneSingleGameMatch() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let saved = try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfOne,
            teamAName: "The Smashers",
            teamBName: "Net Ninjas",
            gameScores: [(teamA: 11, teamB: 7)]
        )

        XCTAssertEqual(saved.winningTeam, .teamA)
        XCTAssertEqual(saved.games?.count, 1)
        let game = try XCTUnwrap(saved.games?.first)
        XCTAssertEqual(game.teamAFinalScore, 11)
        XCTAssertEqual(game.teamBFinalScore, 7)
        XCTAssertTrue(game.orderedPoints.isEmpty, "a quick-logged game has no point-by-point log")
        XCTAssertNil(game.completedAt, "a quick-logged game has no live timing data")
    }

    func testBestOfThreeDecidedTwoNilOnlyCreatesTwoGameRecords() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let saved = try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfThree,
            teamAName: "A",
            teamBName: "B",
            gameScores: [(teamA: 11, teamB: 7), (teamA: 11, teamB: 4)]
        )

        XCTAssertEqual(saved.games?.count, 2)
        XCTAssertEqual(saved.winningTeam, .teamA)
    }

    func testATrailingGameEntryAfterTheMatchIsAlreadyDecidedIsRejected() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        // Best of 3, already 2-0 after two games — a 3rd entry is invalid,
        // not an extra game to silently tack on.
        XCTAssertThrowsError(try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfThree,
            teamAName: "A",
            teamBName: "B",
            gameScores: [(teamA: 11, teamB: 7), (teamA: 11, teamB: 4), (teamA: 11, teamB: 2)]
        )) { error in
            XCTAssertEqual(error as? MatchRepositoryError, .invalidGameScore)
        }
    }

    func testAnIncompleteOrInvalidFinalGameScoreIsRejected() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        // 11-10 violates win-by-2.
        XCTAssertThrowsError(try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            gameScores: [(teamA: 11, teamB: 10)]
        )) { error in
            XCTAssertEqual(error as? MatchRepositoryError, .invalidGameScore)
        }
    }

    func testSavingBeforeAnyTeamHasReachedGamesToWinThrowsMatchNotOver() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        // Best of 3 needs 2 wins; only 1 game entered.
        XCTAssertThrowsError(try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfThree,
            teamAName: "A",
            teamBName: "B",
            gameScores: [(teamA: 11, teamB: 7)]
        )) { error in
            XCTAssertEqual(error as? MatchRepositoryError, .matchNotOver)
        }
    }

    func testSavedMatchAppearsInFetchMatchHistory() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        _ = try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            gameScores: [(teamA: 11, teamB: 7)]
        )

        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 1)
    }
}
