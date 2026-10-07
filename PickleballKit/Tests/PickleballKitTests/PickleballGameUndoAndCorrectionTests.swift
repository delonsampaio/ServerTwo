import XCTest
@testable import PickleballKit

final class PickleballGameUndoAndCorrectionTests: XCTestCase {
    func testUndoRestoresPreviousScoreAndServer() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamB) // full side-out: teamB now serving
        XCTAssertEqual(game.state.servingTeam, .teamB)
        game.undo()
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.state.serverNumber, .two)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoWithEmptyHistoryIsNoOp() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoAfterMultiplePointsStepsBackOneAtATime() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamA) // 1-0
        game.recordPoint(for: .teamA) // 2-0
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 1)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
    }

    func testCorrectScoreSetsScoreDirectly() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.correctScore(team: .teamA, to: 7)
        XCTAssertEqual(game.state.teamAScore, 7)
    }

    func testCorrectScoreIsUndoable() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.correctScore(team: .teamA, to: 7)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
    }

    func testCorrectScoreCanReverseACompletedGameBackToInProgress() {
        // Review Focus: disputes are often about the final point.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...11 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isGameOver)

        game.correctScore(team: .teamA, to: 9) // the last two points were a mistake
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.gameWinner)
    }
}
