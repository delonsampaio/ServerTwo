import XCTest
@testable import PickleballKit

final class GameConfigurationReachableScoreTests: XCTestCase {
    private let elevenWinByTwo = GameConfiguration(winningScore: .eleven, winByTwo: true)

    func testNegativeScoresAreUnreachable() {
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: -1, teamB: 5))
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 5, teamB: -1))
    }

    func testAnyScoreBelowTheTargetIsReachable() {
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 0, teamB: 0))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 3, teamB: 0))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 10, teamB: 10))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 10, teamB: 9))
    }

    func testCompletedFinalsAreReachable() {
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 9))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 0))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 12, teamB: 10))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 13, teamB: 11))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 9, teamB: 11))
    }

    func testInProgressScoresAtOrAboveTheTargetAreReachableWhenTiedOrOneAhead() {
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 10))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 11))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 12, teamB: 11))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 12, teamB: 12))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 12))
    }

    func testOvershotScoresWithAMarginOfThreeOrMoreAreUnreachable() {
        // 12-9 / 13-10 / 15-3: the game would already have ended earlier, and
        // more points can never produce an exact 2-point overtime margin.
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 12, teamB: 9))
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 9, teamB: 12))
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 13, teamB: 10))
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 15, teamB: 3))
    }

    func testWinByTwoOffOnlyAllowsAnExactTargetFinalOrBelow() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: false)
        XCTAssertTrue(config.isReachableGameScore(teamA: 11, teamB: 10))   // completed: first to 11
        XCTAssertTrue(config.isReachableGameScore(teamA: 11, teamB: 0))
        XCTAssertTrue(config.isReachableGameScore(teamA: 10, teamB: 10))   // below target
        XCTAssertFalse(config.isReachableGameScore(teamA: 12, teamB: 10))  // would have ended at 11-10
        XCTAssertFalse(config.isReachableGameScore(teamA: 11, teamB: 11))  // would have ended at 11-10
        XCTAssertFalse(config.isReachableGameScore(teamA: 12, teamB: 12))
    }

    func testFreezeIsPermissiveForEveryNonNegativePair() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: true), winningScore: .eleven, winByTwo: true)
        XCTAssertTrue(config.isReachableGameScore(teamA: 20, teamB: 3))
        XCTAssertTrue(config.isReachableGameScore(teamA: 12, teamB: 9))
        XCTAssertTrue(config.isReachableGameScore(teamA: 0, teamB: 0))
        XCTAssertFalse(config.isReachableGameScore(teamA: -1, teamB: 0))
    }

    func testRallyWithoutFreezeUsesTheSameRulesAsSideOut() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)
        XCTAssertFalse(config.isReachableGameScore(teamA: 12, teamB: 9))
        XCTAssertTrue(config.isReachableGameScore(teamA: 12, teamB: 11))
    }

    func testFifteenAndTwentyOnePointTargets() {
        let fifteen = GameConfiguration(winningScore: .fifteen, winByTwo: true)
        XCTAssertTrue(fifteen.isReachableGameScore(teamA: 15, teamB: 13))
        XCTAssertTrue(fifteen.isReachableGameScore(teamA: 15, teamB: 14))   // in progress
        XCTAssertTrue(fifteen.isReachableGameScore(teamA: 14, teamB: 14))
        XCTAssertFalse(fifteen.isReachableGameScore(teamA: 16, teamB: 13))

        let twentyOne = GameConfiguration(winningScore: .twentyOne, winByTwo: true)
        XCTAssertTrue(twentyOne.isReachableGameScore(teamA: 21, teamB: 19))
        XCTAssertTrue(twentyOne.isReachableGameScore(teamA: 20, teamB: 20))
        XCTAssertTrue(twentyOne.isReachableGameScore(teamA: 21, teamB: 20))
        XCTAssertFalse(twentyOne.isReachableGameScore(teamA: 22, teamB: 19))
    }
}
