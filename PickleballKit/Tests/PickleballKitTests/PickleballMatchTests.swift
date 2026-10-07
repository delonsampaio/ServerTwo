import XCTest
@testable import PickleballKit

final class PickleballMatchTests: XCTestCase {
    func testMatchStartsWithFreshGameAndZeroGamesWon() {
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA)
        XCTAssertEqual(match.gamesWon[.teamA], 0)
        XCTAssertEqual(match.gamesWon[.teamB], 0)
        XCTAssertFalse(match.isMatchOver)
    }

    func testWinningAGameAdvancesToANewGameWithWinnerServingFirst() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        XCTAssertEqual(match.gamesWon[.teamA], 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertFalse(match.isMatchOver) // best of 3 needs 2 games won
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.servingTeam, .teamA) // winner serves next game
    }

    func testWinningEnoughGamesEndsTheMatch() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA)
        for _ in 1...2 {
            for _ in 1...11 { match.recordPoint(for: .teamA) }
        }
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon[.teamA], 2)
    }

    func testRecordPointIsNoOpOnceMatchIsOver() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        XCTAssertTrue(match.isMatchOver)
        match.recordPoint(for: .teamB)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
    }

    func testUndoWithinTheCurrentGameDelegatesToIt() {
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA)
        match.recordPoint(for: .teamA)
        match.undo()
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
    }

    func testUndoAcrossACompletedGameBoundaryRestoresExactPriorState() {
        // Review Focus: must restore the exact prior game's score/server
        // state, not just decrement a counter and start a blank game.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA)
        for _ in 1...11 { match.recordPoint(for: .teamA) } // game 1 won by teamA, 11-0
        XCTAssertEqual(match.gamesWon[.teamA], 1)
        XCTAssertEqual(match.completedGames.count, 1)

        match.undo() // currentGame (game 2) has no history -> cross-boundary undo

        XCTAssertEqual(match.gamesWon[.teamA], 0)
        XCTAssertEqual(match.completedGames.count, 0)
        XCTAssertEqual(match.currentGame.state.teamAScore, 10) // game 1's second-to-last state
        XCTAssertFalse(match.currentGame.isGameOver)
    }
}
