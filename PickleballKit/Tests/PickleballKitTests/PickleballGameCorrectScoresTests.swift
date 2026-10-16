import XCTest
@testable import PickleballKit

final class PickleballGameCorrectScoresTests: XCTestCase {
    private func makeGame(_ configuration: GameConfiguration = GameConfiguration(winningScore: .eleven, winByTwo: true)) -> PickleballGame {
        PickleballGame(configuration: configuration, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    }

    func testCorrectScoresSetsBothScores() {
        let game = makeGame()
        game.correctScores(teamA: 7, teamB: 4)
        XCTAssertEqual(game.state.teamAScore, 7)
        XCTAssertEqual(game.state.teamBScore, 4)
    }

    func testCorrectScoresIsASingleUndoStep() {
        let game = makeGame()
        game.correctScores(teamA: 7, teamB: 4)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
        XCTAssertFalse(game.canUndo, "one correction must add exactly one history entry")
    }

    func testCorrectScoresClampsNegativeValuesToZero() {
        let game = makeGame()
        game.correctScores(teamA: -3, teamB: 5)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 5)
    }

    func testCorrectScoresTriggersTheSideSwitchWhenEitherTeamCrossesTheThreshold() {
        // Threshold for an 11-point game is 6.
        let viaTeamB = makeGame()
        viaTeamB.correctScores(teamA: 2, teamB: 6)
        XCTAssertTrue(viaTeamB.state.hasSideSwitched)

        let viaTeamA = makeGame()
        viaTeamA.correctScores(teamA: 6, teamB: 2)
        XCTAssertTrue(viaTeamA.state.hasSideSwitched)

        let neither = makeGame()
        neither.correctScores(teamA: 5, teamB: 5)
        XCTAssertFalse(neither.state.hasSideSwitched)
    }

    func testCorrectScoresDoesNotValidateReachability() {
        // The engine trusts its caller (the UI gates via isReachableGameScore):
        // an unreachable pair is set as given, and is simply not a completed game.
        let game = makeGame()
        game.correctScores(teamA: 12, teamB: 9)
        XCTAssertEqual(game.state.teamAScore, 12)
        XCTAssertEqual(game.state.teamBScore, 9)
        XCTAssertNil(game.gameWinner)
    }

    func testCorrectScoresForcesLastPointWonWhileServingSoAFrozenGameCanEnd() {
        // Same setup as the existing single-team freeze test: reach a frozen 11-9.
        let config = GameConfiguration(scoringFormat: .rally(freeze: true), winningScore: .eleven, winByTwo: true)
        let game = makeGame(config)
        for _ in 1...10 { game.recordPoint(for: .teamA) }
        for _ in 1...9 { game.recordPoint(for: .teamB) }
        game.recordPoint(for: .teamA)
        XCTAssertEqual(game.state.teamAScore, 11)
        XCTAssertEqual(game.state.teamBScore, 9)
        XCTAssertFalse(game.isGameOver, "frozen: the winning point was won on receive")

        game.correctScores(teamA: 11, teamB: 9)

        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }

    func testSingleTeamCorrectScoreKeepsTheOtherTeamsScoreAndIsOneUndoStep() {
        let game = makeGame()
        game.correctScores(teamA: 5, teamB: 3)
        game.correctScore(team: .teamA, to: 8)
        XCTAssertEqual(game.state.teamAScore, 8)
        XCTAssertEqual(game.state.teamBScore, 3)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 5)
        XCTAssertEqual(game.state.teamBScore, 3)
    }
}
