import XCTest
@testable import PickleballKit

final class PickleballMatchTests: XCTestCase {
    func testMatchStartsWithFreshGameAndZeroGamesWon() {
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertEqual(match.gamesWon[.teamA], 0)
        XCTAssertEqual(match.gamesWon[.teamB], 0)
        XCTAssertFalse(match.isMatchOver)
    }

    func testWinningAGameAdvancesToANewGameWithWinnerServingFirst() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        XCTAssertEqual(match.gamesWon[.teamA], 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertFalse(match.isMatchOver) // best of 3 needs 2 games won
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.servingTeam, .teamA) // winner serves next game
    }

    func testWinningEnoughGamesEndsTheMatch() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...2 {
            for _ in 1...11 { match.recordPoint(for: .teamA) }
        }
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon[.teamA], 2)
    }

    func testRecordPointIsNoOpOnceMatchIsOver() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        XCTAssertTrue(match.isMatchOver)
        match.recordPoint(for: .teamB)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
    }

    func testUndoWithinTheCurrentGameDelegatesToIt() {
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        match.recordPoint(for: .teamA)
        match.undo()
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
    }

    func testUndoAcrossACompletedGameBoundaryRestoresExactPriorState() {
        // Review Focus: must restore the exact prior game's score/server
        // state, not just decrement a counter and start a blank game.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) } // game 1 won by teamA, 11-0
        XCTAssertEqual(match.gamesWon[.teamA], 1)
        XCTAssertEqual(match.completedGames.count, 1)

        match.undo() // currentGame (game 2) has no history -> cross-boundary undo

        XCTAssertEqual(match.gamesWon[.teamA], 0)
        XCTAssertEqual(match.completedGames.count, 0)
        XCTAssertEqual(match.currentGame.state.teamAScore, 10) // game 1's second-to-last state
        XCTAssertFalse(match.currentGame.isGameOver)
    }

    func testUndoOnTheMatchDecidingPointReversesTheWinCount() {
        // Critical bug fix: when a point finishes both the game AND the match,
        // currentGame is aliased with completedGames.last (not reassigned).
        // Undoing must reverse gamesWon, not just revert the score in-place.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon[.teamA], 1)

        match.undo()

        XCTAssertFalse(match.isMatchOver)
        XCTAssertNil(match.matchWinner)
        XCTAssertEqual(match.gamesWon[.teamA], 0)
        XCTAssertFalse(match.currentGame.isGameOver)
        XCTAssertEqual(match.currentGame.state.teamAScore, 10)
    }

    // MARK: - Fix 2: PickleballMatch forwards correctScore/requestTimeout/isPaywalled/unlockPro

    func testCorrectScoreOnMatchThatPushesCurrentGameToAWinAdvancesTheMatch() {
        // Mirrors testWinningAGameAdvancesToANewGameWithWinnerServingFirst,
        // but drives the win via match.correctScore instead of recordPoint,
        // which must keep gamesWon/completedGames/currentGame in sync just
        // like the recordPoint path does.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...10 { match.recordPoint(for: .teamA) }
        XCTAssertFalse(match.currentGame.isGameOver)

        match.correctScore(team: .teamA, to: 11)

        XCTAssertEqual(match.gamesWon[.teamA], 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertFalse(match.isMatchOver) // best of 3 needs 2 games won
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.servingTeam, .teamA) // winner serves next game
    }

    func testCorrectScoreOnMatchThatReversesAMatchDecidingGameUnsticksTheMatch() {
        // Critical: correcting a completed, match-deciding game back to
        // in-progress must undo the match-level bookkeeping too, not just
        // the score -- otherwise isMatchOver/gamesWon stay permanently wrong
        // and recordPoint never works again (guarded by `!isMatchOver`).
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.gamesWon[.teamA], 1)

        match.correctScore(team: .teamA, to: 9) // the last two points were a mistake

        XCTAssertFalse(match.isMatchOver)
        XCTAssertNil(match.matchWinner)
        XCTAssertEqual(match.gamesWon[.teamA], 0)
        XCTAssertFalse(match.currentGame.isGameOver)

        // recordPoint must not be permanently stuck -- replaying to the
        // target must win the match again.
        match.recordPoint(for: .teamA) // 10
        match.recordPoint(for: .teamA) // 11
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon[.teamA], 1)
    }

    func testMatchRequestTimeoutForwardsToCurrentGame() {
        let config = GameConfiguration(timeoutsPerTeam: 2)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertTrue(match.requestTimeout(for: .teamA))
        XCTAssertEqual(match.currentGame.state.timeoutsRemaining(for: .teamA), 1)
    }

    func testMatchIsPaywalledAndUnlockProForwardToCurrentGame() {
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        for _ in 1...5 { match.recordPoint(for: .teamA) }
        XCTAssertTrue(match.isPaywalled)
        XCTAssertEqual(match.isPaywalled, match.currentGame.isPaywalled)

        match.unlockPro()
        XCTAssertFalse(match.isPaywalled)
        XCTAssertTrue(match.currentGame.proUnlocked)
    }

    func testMatchGamesWonForTeamForwardsToTheDictionary() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertEqual(match.gamesWon(for: .teamB), 0)

        for _ in 1...11 { match.recordPoint(for: .teamA) }

        XCTAssertEqual(match.gamesWon(for: .teamA), match.gamesWon[.teamA])
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
    }
}
