import XCTest
@testable import PickleballKit

final class CoreTypesTests: XCTestCase {
    func testTeamOpponent() {
        XCTAssertEqual(Team.teamA.opponent, .teamB)
        XCTAssertEqual(Team.teamB.opponent, .teamA)
    }

    func testSideSwitchThresholds() {
        XCTAssertEqual(WinningScore.eleven.sideSwitchThreshold, 6)
        XCTAssertEqual(WinningScore.fifteen.sideSwitchThreshold, 8)
        XCTAssertEqual(WinningScore.twentyOne.sideSwitchThreshold, 11)
    }

    func testGamesToWin() {
        XCTAssertEqual(MatchFormat.bestOfOne.gamesToWin, 1)
        XCTAssertEqual(MatchFormat.bestOfThree.gamesToWin, 2)
        XCTAssertEqual(MatchFormat.bestOfFive.gamesToWin, 3)
    }

    func testGameConfigurationDefaults() {
        let config = GameConfiguration()
        XCTAssertEqual(config.playMode, .doubles)
        XCTAssertEqual(config.scoringFormat, .sideOut)
        XCTAssertEqual(config.winningScore, .eleven)
        XCTAssertTrue(config.winByTwo)
        XCTAssertEqual(config.timeoutsPerTeam, 2)
    }

    func testCoinFlipIsDeterministicWithSeededGenerator() {
        // A generator that always returns the same raw value must always
        // produce the same team — verified against the real stdlib
        // behavior: Bool.random(using:) with a generator fixed at
        // UInt64.max evaluates to false, i.e. .teamB.
        struct FixedGenerator: RandomNumberGenerator {
            func next() -> UInt64 { UInt64.max }
        }
        var generator = FixedGenerator()
        let result = CoinFlip.flip(using: &generator)
        XCTAssertEqual(result, .teamB)
    }
}
