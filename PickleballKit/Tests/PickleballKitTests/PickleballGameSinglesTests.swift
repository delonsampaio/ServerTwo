import XCTest
@testable import PickleballKit

final class PickleballGameSinglesTests: XCTestCase {
    func testNewSinglesGameStartsAtServerOne() {
        let config = GameConfiguration(playMode: .singles)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertEqual(game.state.serverNumber, .one)
    }

    func testSinglesSideOutIsImmediateRegardlessOfServerNumber() {
        let config = GameConfiguration(playMode: .singles)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.recordPoint(for: .teamB) // immediate side-out, no Server 2 phase
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.state.serverNumber, .one)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
    }

    func testSinglesServingTeamScoringKeepsServe() {
        let config = GameConfiguration(playMode: .singles)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.recordPoint(for: .teamA)
        game.recordPoint(for: .teamA)
        XCTAssertEqual(game.state.teamAScore, 2)
        XCTAssertEqual(game.state.servingTeam, .teamA)
    }
}
