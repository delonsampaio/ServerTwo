import XCTest
@testable import PickleballKit

final class PickleballGameTimeoutsAndSideSwitchTests: XCTestCase {
    func testTimeoutIsGrantedAndDecrements() {
        let game = PickleballGame(configuration: GameConfiguration(timeoutsPerTeam: 2), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertTrue(game.requestTimeout(for: .teamA))
        XCTAssertEqual(game.state.timeoutsRemaining(for: .teamA), 1)
    }

    func testTimeoutIsDeniedWhenNoneRemaining() {
        let game = PickleballGame(configuration: GameConfiguration(timeoutsPerTeam: 1), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertTrue(game.requestTimeout(for: .teamA))
        XCTAssertFalse(game.requestTimeout(for: .teamA))
        XCTAssertEqual(game.state.timeoutsRemaining(for: .teamA), 0)
    }

    func testSideSwitchTriggersAtThresholdForGameToEleven() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertFalse(game.state.hasSideSwitched)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertFalse(game.state.hasSideSwitched) // 5 points, threshold is 6
        game.recordPoint(for: .teamA)
        XCTAssertTrue(game.state.hasSideSwitched) // 6 points, threshold reached
    }

    func testSideSwitchOnlyTriggersOnce() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...6 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.state.hasSideSwitched)
        game.recordPoint(for: .teamB)
        XCTAssertTrue(game.state.hasSideSwitched) // still true, not reset
    }

    // MARK: - Fix 4: requestTimeout edge case

    func testRequestTimeoutIsDeniedOnceTheGameIsOver() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true, timeoutsPerTeam: 2)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isGameOver)

        XCTAssertFalse(game.requestTimeout(for: .teamA))
        XCTAssertEqual(game.state.timeoutsRemaining(for: .teamA), 2) // unchanged
    }
}
