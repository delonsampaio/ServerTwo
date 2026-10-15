import XCTest
@testable import PickleballKit

final class GameConfigurationCompletedScoreTests: XCTestCase {
    func testBelowWinningScoreIsNotCompleted() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        XCTAssertFalse(config.isCompletedGameScore(teamA: 9, teamB: 7))
    }

    func testTiedScoreIsNotCompletedEvenAboveWinningScore() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        XCTAssertFalse(config.isCompletedGameScore(teamA: 12, teamB: 12))
    }

    func testWinByTwoViolationIsRejected() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        XCTAssertFalse(config.isCompletedGameScore(teamA: 11, teamB: 10))
    }

    func testExactWinningScoreIsAccepted() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        XCTAssertTrue(config.isCompletedGameScore(teamA: 11, teamB: 7))
    }

    func testWinByTwoSatisfiedWithExtraMarginIsAccepted() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        XCTAssertTrue(config.isCompletedGameScore(teamA: 11, teamB: 0))
    }

    func testExactOvertimeMarginOfTwoIsAccepted() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        XCTAssertTrue(config.isCompletedGameScore(teamA: 15, teamB: 13))
    }

    func testWithWinByTwoDisabledReachingTheWinningScoreByOnePointIsAccepted() {
        // With winByTwo off, the game ends the instant anyone reaches 11,
        // regardless of the opponent's score.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: false)
        XCTAssertTrue(config.isCompletedGameScore(teamA: 11, teamB: 10))
    }

    func testWithWinByTwoDisabledAnOvertimeMarginIsUnreachableAndRejected() {
        // 12-10 could never happen with winByTwo off — the game would
        // already have ended at 11-10.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: false)
        XCTAssertFalse(config.isCompletedGameScore(teamA: 12, teamB: 10))
    }

    func testImpossibleOvertimeMarginIsRejected() {
        // 15-10 in an 11-point win-by-2 game is unreachable: the game would
        // have already ended at 11-9 or 12-10.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        XCTAssertFalse(config.isCompletedGameScore(teamA: 15, teamB: 10))
    }

    func testNegativeScoresAreRejected() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        XCTAssertFalse(config.isCompletedGameScore(teamA: -1, teamB: 7))
    }

    func testRallyFreezeAcceptsALargeOvertimeMarginUnconstrained() {
        // Freeze's margin is deliberately unconstrained — a point can satisfy
        // the score-win-condition while being won on receive, which doesn't
        // end the game (see the doc comment on isCompletedGameScore).
        let config = GameConfiguration(scoringFormat: .rally(freeze: true), winningScore: .eleven, winByTwo: true)
        XCTAssertTrue(config.isCompletedGameScore(teamA: 20, teamB: 11))
    }
}
