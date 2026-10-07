import XCTest
@testable import PickleballKit

final class PickleballGameDoublesSideOutTests: XCTestCase {
    func testNewDoublesGameStartsAtServerTwo() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.state.serverNumber, .two)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
    }

    func testServingTeamScoringKeepsServe() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamA)
        XCTAssertEqual(game.state.teamAScore, 1)
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.state.serverNumber, .two)
    }

    func testFirstGameServerTwoLosingRallyCausesFullSideOut() {
        // The very first server of a new game is Server 2, so losing their
        // first rally is a full side-out straight to the other team.
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamB)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.state.serverNumber, .one)
    }

    func testSecondServerLosingRallyCausesFullSideOut() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        // Team A wins a point as Server 2, then loses: Server 2 losing a
        // rally always fully sides out, regardless of whether it was the
        // game's very first service turn.
        game.recordPoint(for: .teamA)
        game.recordPoint(for: .teamB)
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.state.serverNumber, .one)
    }

    func testServerOneLosingRallyAdvancesToServerTwoWithoutChangingTeam() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamB) // side-out: teamB now serving, Server 1
        game.recordPoint(for: .teamA) // teamB's Server 1 loses the rally
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.state.serverNumber, .two)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
    }

    func testLongStreakOfConsecutivePointsNeverMisfiresRotation() {
        // Review Focus: many consecutive points to the same server must
        // never erroneously flip server/team.
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        for expectedScore in 1...10 {
            game.recordPoint(for: .teamA)
            XCTAssertEqual(game.state.teamAScore, expectedScore)
            XCTAssertEqual(game.state.servingTeam, .teamA)
            XCTAssertEqual(game.state.serverNumber, .two)
        }
    }

    func testGameEndsAtWinningScoreWithSufficientMargin() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...11 {
            game.recordPoint(for: .teamA)
        }
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }
}
