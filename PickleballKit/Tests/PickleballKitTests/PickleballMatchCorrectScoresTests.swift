import XCTest
@testable import PickleballKit

final class PickleballMatchCorrectScoresTests: XCTestCase {
    private let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

    private func makeMatch(_ format: MatchFormat) -> PickleballMatch {
        PickleballMatch(configuration: config, matchFormat: format, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    }

    // MARK: - UI-reachable paths

    func testTwoTeamCorrectionThroughAnIntermediateScoreNeverEndsTheGame() {
        // 9-9 -> 12-11 in one step. Done as two single-team edits, the first
        // write (12-9) was the problem; the atomic call evaluates only 12-11.
        let match = makeMatch(.bestOfOne)
        match.correctScores(teamA: 9, teamB: 9)
        match.correctScores(teamA: 12, teamB: 11)

        XCTAssertEqual(match.currentGame.state.teamAScore, 12)
        XCTAssertEqual(match.currentGame.state.teamBScore, 11)
        XCTAssertFalse(match.isMatchOver)
        XCTAssertTrue(match.completedGames.isEmpty)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)

        match.undo()   // one undo restores BOTH scores
        XCTAssertEqual(match.currentGame.state.teamAScore, 9)
        XCTAssertEqual(match.currentGame.state.teamBScore, 9)
        match.undo()
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
    }

    func testCorrectingToTheTargetWhileOnlyOnePointAheadStaysInProgress() {
        // The opponent is one point from the target (10); the corrected pair
        // reaches the target but leads by only one, so win-by-2 keeps it live.
        let match = makeMatch(.bestOfOne)
        match.correctScores(teamA: 9, teamB: 10)
        match.correctScores(teamA: 11, teamB: 10)

        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertEqual(match.currentGame.state.teamAScore, 11)
        XCTAssertEqual(match.currentGame.state.teamBScore, 10)
    }

    func testCorrectionThatCompletesANonFinalGameArchivesItAndOneUndoRestoresEverything() {
        let match = makeMatch(.bestOfThree)
        match.correctScores(teamA: 11, teamB: 9)

        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertEqual(match.completedGames[0].state.teamAScore, 11)
        XCTAssertEqual(match.completedGames[0].state.teamBScore, 9)
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)   // fresh game 2
        XCTAssertEqual(match.currentGame.state.servingTeam, .teamA)
        XCTAssertFalse(match.isMatchOver)

        match.undo()   // Branch 3: pops the archived game and undoes the correction

        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertTrue(match.completedGames.isEmpty)
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertFalse(match.currentGameIsCounted)
    }

    func testCorrectionThatCompletesTheFinalGameEndsTheMatchAndOneUndoRestoresEverything() {
        let match = makeMatch(.bestOfThree)
        for _ in 1...11 { match.recordPoint(for: .teamA) }   // game 1: A wins 11-0
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)

        match.correctScores(teamA: 11, teamB: 9)              // game 2: A wins -> match over

        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon(for: .teamA), 2)
        XCTAssertEqual(match.completedGames.count, 2)
        XCTAssertTrue(match.currentGameIsCounted)

        match.undo()   // Branch 1

        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertFalse(match.currentGameIsCounted)
    }

    func testUndoingTheMatchDecidingPointStillUncountsTheGame() {
        // Guards the undo() refactor: normal play must be unchanged.
        let match = makeMatch(.bestOfOne)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        XCTAssertTrue(match.isMatchOver)

        match.undo()

        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertTrue(match.completedGames.isEmpty)
        XCTAssertEqual(match.currentGame.state.teamAScore, 10)
        XCTAssertFalse(match.currentGameIsCounted)
    }

    func testCorrectionThatCrossesTheSideSwitchThresholdAndEndsTheMatchLeavesBothFlagsSet() {
        // 0-0 -> 11-9 in a best-of-1: the game ends AND `hasSideSwitched`
        // flips on the finished game. The engine reports both; ScoringView
        // must not show "Side Switch" when `match.isMatchOver` (Task 5).
        let match = makeMatch(.bestOfOne)
        match.correctScores(teamA: 11, teamB: 9)

        XCTAssertTrue(match.isMatchOver)
        XCTAssertTrue(match.currentGame.state.hasSideSwitched)
    }

    // MARK: - Engine-only paths (UI-unreachable, but real invariants)
    // The next three FAIL against the pre-fix undo() — see Step 4.

    func testUndoingACorrectionThatUncountedADecidedGameRecountsIt() {
        let match = makeMatch(.bestOfOne)
        for _ in 1...11 { match.recordPoint(for: .teamA) }   // 11-0, counted
        match.correctScores(teamA: 10, teamB: 10)            // un-counts
        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)

        match.undo()                                          // back to 11-0

        XCTAssertEqual(match.currentGame.state.teamAScore, 11)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertTrue(match.currentGameIsCounted)
    }

    func testUndoingACorrectionThatFlippedTheWinnerRestoresTheOriginalWinner() {
        let match = makeMatch(.bestOfOne)
        for _ in 1...11 { match.recordPoint(for: .teamA) }   // 11-0, A wins
        match.correctScores(teamA: 9, teamB: 11)             // flips: B wins
        XCTAssertEqual(match.matchWinner, .teamB)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertEqual(match.gamesWon(for: .teamB), 1)

        match.undo()                                          // back to 11-0

        XCTAssertEqual(match.currentGame.state.teamAScore, 11)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.gamesWon(for: .teamB), 0)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertTrue(match.currentGameIsCounted)
    }

    func testUndoingACorrectionThatLeftTheWinnerUnchangedKeepsTheGameCounted() {
        let match = makeMatch(.bestOfOne)
        for _ in 1...11 { match.recordPoint(for: .teamA) }   // 11-0, A wins
        match.correctScores(teamA: 11, teamB: 7)             // still A wins
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)

        match.undo()                                          // back to 11-0

        XCTAssertEqual(match.currentGame.state.teamAScore, 11)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertTrue(match.currentGameIsCounted)
    }
}
