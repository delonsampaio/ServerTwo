import XCTest
@testable import PickleballKit

final class PickleballGameUndoAndCorrectionTests: XCTestCase {
    func testUndoRestoresPreviousScoreAndServer() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.recordPoint(for: .teamB) // full side-out: teamB now serving
        XCTAssertEqual(game.state.servingTeam, .teamB)
        game.undo()
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.state.serverNumber, .two)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoWithEmptyHistoryIsNoOp() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoAfterMultiplePointsStepsBackOneAtATime() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.recordPoint(for: .teamA) // 1-0
        game.recordPoint(for: .teamA) // 2-0
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 1)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
    }

    func testCorrectScoreSetsScoreDirectly() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.correctScore(team: .teamA, to: 7)
        XCTAssertEqual(game.state.teamAScore, 7)
    }

    func testCorrectScoreIsUndoable() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.correctScore(team: .teamA, to: 7)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
    }

    func testCorrectScoreCanReverseACompletedGameBackToInProgress() {
        // Review Focus: disputes are often about the final point.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isGameOver)

        game.correctScore(team: .teamA, to: 9) // the last two points were a mistake
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.gameWinner)
    }

    // MARK: - Fix 4: correctScore edge cases

    func testCorrectScoreClampsNegativeValuesToZero() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.correctScore(team: .teamA, to: -5)
        XCTAssertEqual(game.state.teamAScore, 0)
    }

    func testCorrectScoreTriggersSideSwitchWhenCrossingTheThreshold() {
        let config = GameConfiguration(winningScore: .eleven) // threshold is 6
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertFalse(game.state.hasSideSwitched)

        game.correctScore(team: .teamA, to: 6)

        XCTAssertTrue(game.state.hasSideSwitched)
    }

    func testCorrectScoreOverridesLastPointWonWhileServingSoAFreezeGameCanEnd() {
        // A manual correction always sets lastPointWonWhileServing = true,
        // which lets a human-driven correction end a rally+freeze game even
        // when the frozen "serve just changed hands" subtlety was blocking
        // a natural win (see testFreezeBlocksWinOnTheExactRallyServeChangesHands).
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: true),
            winningScore: .eleven,
            winByTwo: true
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...10 { game.recordPoint(for: .teamA) } // 10-0, teamA serving throughout
        for _ in 1...9 { game.recordPoint(for: .teamB) }  // teamB takes over serve, climbs to 9: 10-9
        game.recordPoint(for: .teamA) // 11-9, but frozen: serve just changed hands this rally
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.gameWinner)

        // A human correction to the same 11-9 score overrides the freeze.
        game.correctScore(team: .teamA, to: 11)

        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }
}
