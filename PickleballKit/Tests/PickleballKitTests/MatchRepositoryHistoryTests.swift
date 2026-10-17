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

    func testSaveCompletedMatchAppliesGameCompletionDatesByPosition() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)

        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        let firstGameEnd = Date(timeIntervalSince1970: 1000)
        let secondGameEnd = Date(timeIntervalSince1970: 2000)

        let saved = try repository.saveCompletedMatch(
            match,
            teamAName: "A",
            teamBName: "B",
            startedAt: Date(timeIntervalSince1970: 0),
            gameCompletionDates: [firstGameEnd, secondGameEnd]
        )

        let games = try XCTUnwrap(saved.games).sorted { $0.gameNumber < $1.gameNumber }
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games[0].completedAt, firstGameEnd)
        XCTAssertEqual(games[1].completedAt, secondGameEnd)
    }

    func testSaveCompletedMatchOmittingGameCompletionDatesLeavesEveryGameNil() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        // No gameCompletionDates argument at all — every existing caller in
        // this file (and in the app) must keep compiling unchanged.
        let saved = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())

        let game = try XCTUnwrap(saved.games?.first)
        XCTAssertNil(game.completedAt)
    }

    func testSaveCompletedMatchToleratesShorterGameCompletionDatesThanGames() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)

        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        // Only one date for two games — simulates a crash-resumed match whose
        // earlier game predates this session's own timestamp capture. Must
        // degrade to nil for the uncovered game, not crash.
        let onlyDate = Date(timeIntervalSince1970: 500)
        let saved = try repository.saveCompletedMatch(
            match,
            teamAName: "A",
            teamBName: "B",
            startedAt: Date(timeIntervalSince1970: 0),
            gameCompletionDates: [onlyDate]
        )

        let games = try XCTUnwrap(saved.games).sorted { $0.gameNumber < $1.gameNumber }
        XCTAssertEqual(games[0].completedAt, onlyDate)
        XCTAssertNil(games[1].completedAt)
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

    func testSaveCompletedMatchKeepsAGameWhoseScoreNoLongerCountsAsCompleted() throws {
        // A match restored from an in-progress snapshot saved BEFORE the strict
        // completed-score rule can hold a decided game at a score the rule no
        // longer recognises (12-9 with win-by-2: only reachable via an old
        // lenient correction). That game must be saved with the higher score
        // as its winner, not silently dropped.
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let finalState = GameState(
            teamAScore: 12, teamBScore: 9,
            servingTeam: .teamA, serverNumber: .one,
            teamATimeoutsRemaining: 2, teamBTimeoutsRemaining: 2,
            hasSideSwitched: true, lastPointWonWhileServing: true
        )
        func makeLegacyGame() -> PickleballGame {
            PickleballGame(configuration: config, state: finalState, history: [], proUnlocked: true, demoPointCap: nil)
        }
        XCTAssertNil(makeLegacyGame().gameWinner, "sanity: 12-9 is not a completed score under the strict rule")

        let match = PickleballMatch(
            configuration: config,
            matchFormat: .bestOfOne,
            completedGames: [makeLegacyGame()],
            currentGame: makeLegacyGame(),
            gamesWon: [.teamA: 1, .teamB: 0],
            currentGameIsCounted: true
        )

        let saved = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())

        XCTAssertEqual(saved.winningTeam, .teamA)
        let games = try XCTUnwrap(saved.games)
        XCTAssertEqual(games.count, 1, "the legacy game must not be dropped")
        let game = try XCTUnwrap(games.first)
        XCTAssertEqual(game.teamAFinalScore, 12)
        XCTAssertEqual(game.teamBFinalScore, 9)
        XCTAssertEqual(game.winningTeam, .teamA)
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

    func testSaveCompletedMatchClearsAnyInProgressSnapshot() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        try repository.saveInProgressSnapshot(for: match, startedAt: Date())
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        _ = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())

        let loaded = try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil)
        XCTAssertNil(loaded, "a finished match must not remain resumable, or it could be saved to history a second time")
    }

    func testFetchedMatchHistoryHasCorrectlyOrderedPointsForEveryGameAfterARealStoreRoundTrip() throws {
        // Re-fetches through fetchMatchHistory (not the in-memory object the
        // save method returned) and descends into a multi-game match's full
        // relationship graph — the exact failure mode the explicit-insert
        // fix exists to prevent.
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) } // game 1: teamA wins 11-0
        // Game 2: teamA wins 11-0, match over (best of 3, 2-0). Team B serves
        // first in game 2 (Rule 21.F.2), so A first wins the side-out;
        // playOutGame handles that. Scored points per game stay 11.
        playOutGame(match, winner: .teamA)

        _ = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())

        let refetched = try repository.fetchMatchHistory()
        let record = try XCTUnwrap(refetched.first)
        let games = try XCTUnwrap(record.games)
        XCTAssertEqual(games.count, 2)

        for game in games.sorted(by: { $0.gameNumber < $1.gameNumber }) {
            let points = game.orderedPoints
            XCTAssertEqual(points.count, 11, "game \(game.gameNumber) should have exactly 11 scored points")
            XCTAssertEqual(points.last?.teamAScoreAfter, 11)
            for (index, point) in points.enumerated() {
                XCTAssertEqual(point.sequenceNumber, index + 1, "sequence numbers must be contiguous after a store round-trip")
            }
        }
    }

    func testFullLifecycleFromInProgressSnapshotThroughResumeToCompletedHistory() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let startedAt = Date(timeIntervalSince1970: 500)

        // Play game 1 partway, autosave mid-game.
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...5 { match.recordPoint(for: .teamA) }
        try repository.saveInProgressSnapshot(for: match, startedAt: startedAt)

        // Simulate a relaunch: resume from the snapshot.
        let resumedAfterPartialGame = try XCTUnwrap(repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil))
        XCTAssertEqual(resumedAfterPartialGame.startedAt, startedAt)
        let resumedMatch = resumedAfterPartialGame.match
        XCTAssertEqual(resumedMatch.currentGame.state.teamAScore, 5)

        // Finish game 1, autosave again right after the match-deciding-for-this-game point.
        for _ in 1...6 { resumedMatch.recordPoint(for: .teamA) } // 11-0, game 1 won
        XCTAssertEqual(resumedMatch.gamesWon(for: .teamA), 1)
        try repository.saveInProgressSnapshot(for: resumedMatch, startedAt: startedAt)

        // Simulate a second relaunch mid-match (not match-deciding this time).
        let resumedAfterGame1 = try XCTUnwrap(repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil))
        let resumedMatch2 = resumedAfterGame1.match
        XCTAssertEqual(resumedMatch2.completedGames.count, 1)
        XCTAssertFalse(resumedMatch2.isMatchOver)

        // Win game 2 to decide the match (best of 3, 2-0). Team B serves
        // first in game 2 (Rule 21.F.2), so playOutGame wins the side-out first.
        playOutGame(resumedMatch2, winner: .teamA)
        XCTAssertTrue(resumedMatch2.isMatchOver)

        // Save to history using the startedAt carried through the snapshot(s).
        let saved = try repository.saveCompletedMatch(
            resumedMatch2,
            teamAName: "The Smashers",
            teamBName: "Net Ninjas",
            startedAt: resumedAfterGame1.startedAt
        )
        XCTAssertEqual(saved.startedAt, startedAt)
        XCTAssertEqual(saved.winningTeam, .teamA)

        // The in-progress snapshot must be gone — nothing left to resume.
        XCTAssertNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil))

        // History reflects the completed match with both games intact.
        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.games?.count, 2)
    }
}
