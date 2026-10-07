import XCTest
@testable import PickleballKit

final class PickleballGameTimeoutsAndSideSwitchTests: XCTestCase {
    func testTimeoutIsGrantedAndDecrements() {
        let game = PickleballGame(configuration: GameConfiguration(timeoutsPerTeam: 2), firstServingTeam: .teamA)
        XCTAssertTrue(game.requestTimeout(for: .teamA))
        XCTAssertEqual(game.state.timeoutsRemaining(for: .teamA), 1)
    }

    func testTimeoutIsDeniedWhenNoneRemaining() {
        let game = PickleballGame(configuration: GameConfiguration(timeoutsPerTeam: 1), firstServingTeam: .teamA)
        XCTAssertTrue(game.requestTimeout(for: .teamA))
        XCTAssertFalse(game.requestTimeout(for: .teamA))
        XCTAssertEqual(game.state.timeoutsRemaining(for: .teamA), 0)
    }

    func testSideSwitchTriggersAtThresholdForGameToEleven() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        XCTAssertFalse(game.state.hasSideSwitched)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertFalse(game.state.hasSideSwitched) // 5 points, threshold is 6
        game.recordPoint(for: .teamA)
        XCTAssertTrue(game.state.hasSideSwitched) // 6 points, threshold reached
    }

    func testSideSwitchOnlyTriggersOnce() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...6 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.state.hasSideSwitched)
        game.recordPoint(for: .teamB)
        XCTAssertTrue(game.state.hasSideSwitched) // still true, not reset
    }
}
