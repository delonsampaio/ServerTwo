import XCTest
@testable import ServerTwo
import PickleballKit

final class ScoringPromptSheetTests: XCTestCase {
    private func title(winner: Team?, a: Int, b: Int, game: Int = 1) -> String {
        ScoringPromptSheet.gameOverTitle(
            gameNumber: game, teamAName: "Delon", teamBName: "Fred",
            teamAScore: a, teamBScore: b, winner: winner
        )
    }

    func testGameOverTitleNamesTheEngineWinner() {
        XCTAssertEqual(title(winner: .teamA, a: 11, b: 6), "Game 1 goes to Delon")
        XCTAssertEqual(title(winner: .teamB, a: 6, b: 11, game: 2), "Game 2 goes to Fred")
    }

    func testGameOverTitleFallsBackToTheHigherScoreWhenNoEngineWinner() {
        XCTAssertEqual(title(winner: nil, a: 11, b: 9), "Game 1 goes to Delon")
        XCTAssertEqual(title(winner: nil, a: 9, b: 11, game: 3), "Game 3 goes to Fred")
    }

    func testGameOverTitleOnAnExactTieWithNoWinnerDoesNotNameAnyone() {
        XCTAssertEqual(title(winner: nil, a: 10, b: 10), "Game 1 is over")
    }

    func testResolvedWinnerKeepsTheEngineWinnerAndOnlyFallsBackWhenNil() {
        XCTAssertEqual(ScoringPromptSheet.resolvedWinner(.teamB, teamAScore: 11, teamBScore: 9), .teamB)
        XCTAssertEqual(ScoringPromptSheet.resolvedWinner(nil, teamAScore: 5, teamBScore: 9), .teamB)
        XCTAssertNil(ScoringPromptSheet.resolvedWinner(nil, teamAScore: 5, teamBScore: 5))
    }

    func testStartNextGameButtonNumbersTheFollowingGame() {
        XCTAssertEqual(ScoringPromptSheet.startNextGameTitle(afterGame: 1), "Start Game 2")
        XCTAssertEqual(ScoringPromptSheet.startNextGameTitle(afterGame: 4), "Start Game 5")
    }

    func testFirstServeLineNamesTheNextGamesFirstServer() {
        XCTAssertEqual(ScoringPromptSheet.firstServeLine(name: "Fred"), "First serve: Fred.")
        XCTAssertEqual(ScoringPromptSheet.firstServeLine(name: "Delon & Katie"), "First serve: Delon & Katie.")
    }

    func testGamesTallyLine() {
        XCTAssertEqual(ScoringPromptSheet.gamesTallyLine(teamAGames: 1, teamBGames: 0), "Games 1 – 0")
    }

    func testGameOverSheetSaysTeamsSwitchSides() {
        XCTAssertEqual(ScoringPromptSheet.switchSidesLine, "Teams switch sides.")
    }

    func testCancelProgressIncludesGamesOnlyWhenGamesWereCompleted() {
        XCTAssertEqual(
            ScoringPromptSheet.cancelProgressSummary(
                teamAScore: 3, teamBScore: 2, teamAGames: 1, teamBGames: 0, completedGameCount: 1
            ),
            "Games 1 – 0, current game 3 – 2"
        )
        XCTAssertEqual(
            ScoringPromptSheet.cancelProgressSummary(
                teamAScore: 3, teamBScore: 2, teamAGames: 0, teamBGames: 0, completedGameCount: 0
            ),
            "Current game 3 – 2"
        )
    }

    func testMatchupLine() {
        XCTAssertEqual(ScoringPromptSheet.matchupLine(teamAName: "Delon", teamBName: "Fred"), "Delon vs Fred")
    }

    func testSideSwitchScoreLine() {
        XCTAssertEqual(
            ScoringPromptSheet.sideSwitchScoreLine(teamAName: "Delon", teamBName: "Fred", teamAScore: 6, teamBScore: 3),
            "Delon 6 – 3 Fred"
        )
    }

    func testPromptIdsAreStablePerCase() {
        XCTAssertEqual(ScoringPrompt.sideSwitch(
                gameIndex: 0, direction: .switchSides, threshold: 6,
                teamAName: "A", teamBName: "B", teamAScore: 1, teamBScore: 0
            ).id, "sideSwitch")
        XCTAssertEqual(
            ScoringPrompt.gameOver(
                gameNumber: 1, teamAName: "A", teamBName: "B", teamAScore: 11, teamBScore: 0,
                winner: .teamA, teamAGames: 1, teamBGames: 0, firstServerName: "B"
            ).id,
            "gameOver"
        )
        XCTAssertEqual(
            ScoringPrompt.cancelMatch(
                teamAName: "A", teamBName: "B", teamAScore: 0, teamBScore: 0,
                teamAGames: 0, teamBGames: 0, completedGameCount: 0
            ).id,
            "cancelMatch"
        )
    }

    func testSwitchBackBodyNamesTheThreshold() {
        XCTAssertEqual(
            ScoringPromptSheet.switchBackBody(threshold: 6),
            "The score is back under 6, so teams return to their starting ends."
        )
        XCTAssertEqual(
            ScoringPromptSheet.switchBackBody(threshold: 8),
            "The score is back under 8, so teams return to their starting ends."
        )
    }

    func testSideSwitchDirectionFromFlagAndPromptedState() {
        XCTAssertEqual(ScoringPrompt.sideSwitchDirection(hasSwitched: true, promptedState: false), .switchSides)
        XCTAssertEqual(ScoringPrompt.sideSwitchDirection(hasSwitched: false, promptedState: true), .switchBack)
        XCTAssertNil(ScoringPrompt.sideSwitchDirection(hasSwitched: true, promptedState: true))
        XCTAssertNil(ScoringPrompt.sideSwitchDirection(hasSwitched: false, promptedState: false))
    }

    func testSideSwitchPromptIsStaleWhenGameOrFlagMovedOn() {
        // Still describes the live court.
        XCTAssertFalse(ScoringPrompt.isSideSwitchStale(
            gameIndex: 1, direction: .switchSides, currentGameIndex: 1, hasSideSwitched: true))
        XCTAssertFalse(ScoringPrompt.isSideSwitchStale(
            gameIndex: 1, direction: .switchBack, currentGameIndex: 1, hasSideSwitched: false))
        // The save that crossed the threshold also ended the game.
        XCTAssertTrue(ScoringPrompt.isSideSwitchStale(
            gameIndex: 0, direction: .switchSides, currentGameIndex: 1, hasSideSwitched: false))
        // Flag flipped again before the prompt could show.
        XCTAssertTrue(ScoringPrompt.isSideSwitchStale(
            gameIndex: 1, direction: .switchSides, currentGameIndex: 1, hasSideSwitched: false))
        XCTAssertTrue(ScoringPrompt.isSideSwitchStale(
            gameIndex: 1, direction: .switchBack, currentGameIndex: 1, hasSideSwitched: true))
    }

    func testOnlySideSwitchPromptsCanBeStale() {
        let gameOver = ScoringPrompt.gameOver(
            gameNumber: 1, teamAName: "A", teamBName: "B", teamAScore: 11, teamBScore: 0,
            winner: .teamA, teamAGames: 1, teamBGames: 0, firstServerName: "B"
        )
        XCTAssertFalse(gameOver.isStale(currentGameIndex: 5, hasSideSwitched: false))
        let sideSwitch = ScoringPrompt.sideSwitch(
            gameIndex: 0, direction: .switchSides, threshold: 6,
            teamAName: "A", teamBName: "B", teamAScore: 6, teamBScore: 0
        )
        XCTAssertFalse(sideSwitch.isStale(currentGameIndex: 0, hasSideSwitched: true))
        XCTAssertTrue(sideSwitch.isStale(currentGameIndex: 1, hasSideSwitched: true))
    }

    // MARK: Game Over acknowledgement

    func testGameOverDecisionPromptsOncePerCompletedGame() {
        var r = ScoringPrompt.gameOverDecision(newCompletedCount: 1, acknowledgedIndex: -1, isMatchOver: false)
        XCTAssertTrue(r.shouldPrompt)
        XCTAssertEqual(r.acknowledgedIndex, 0)
        r = ScoringPrompt.gameOverDecision(newCompletedCount: 1, acknowledgedIndex: 0, isMatchOver: false)
        XCTAssertFalse(r.shouldPrompt)
        XCTAssertEqual(r.acknowledgedIndex, 0)
    }

    func testGameOverDecisionNeverPromptsForTheMatchDecidingGame() {
        let r = ScoringPrompt.gameOverDecision(newCompletedCount: 2, acknowledgedIndex: 0, isMatchOver: true)
        XCTAssertFalse(r.shouldPrompt)
        XCTAssertEqual(r.acknowledgedIndex, 0)
    }

    func testGameOverDecisionLowersTheIndexOnUndoSoAReplayPromptsAgain() {
        // Undo the game-ending point: count 1 -> 0.
        var r = ScoringPrompt.gameOverDecision(newCompletedCount: 0, acknowledgedIndex: 0, isMatchOver: false)
        XCTAssertFalse(r.shouldPrompt)
        XCTAssertEqual(r.acknowledgedIndex, -1)
        // Replay it: count 0 -> 1.
        r = ScoringPrompt.gameOverDecision(newCompletedCount: 1, acknowledgedIndex: r.acknowledgedIndex, isMatchOver: false)
        XCTAssertTrue(r.shouldPrompt)
    }
}

final class SideSwitchPromptTrackerTests: XCTestCase {
    func testFreshMatchPromptsOnceWhenTheFlagFirstSets() {
        var tracker = SideSwitchPromptTracker()
        tracker.seed(completedGameFlags: [], currentGameFlag: false)
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: false))
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: true), .switchSides)
        // Idempotent: a second sync for the same state announces nothing.
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: true))
    }

    func testUnseededTrackerBehavesLikeAFreshMatch() {
        var tracker = SideSwitchPromptTracker()
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: true), .switchSides)
    }

    func testResumedPastTheThresholdDoesNotPromptOnSync() {
        var tracker = SideSwitchPromptTracker()
        tracker.seed(completedGameFlags: [], currentGameFlag: true) // restored at 8-3
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: true))
    }

    func testResumedThenDroppingUnderTheThresholdSwitchesBack() {
        var tracker = SideSwitchPromptTracker()
        tracker.seed(completedGameFlags: [], currentGameFlag: true)
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: false), .switchBack)
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: false))
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: true), .switchSides)
    }

    func testResumedInGameTwoThenUndoingIntoGameOneDoesNotPrompt() {
        var tracker = SideSwitchPromptTracker()
        // Game 1 finished with its flag set; game 2 is fresh.
        tracker.seed(completedGameFlags: [true], currentGameFlag: false)
        XCTAssertNil(tracker.next(gameIndex: 1, hasSwitched: false))
        // Undo back into game 1: flag still true.
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: true))
    }

    func testPerIndexStateKeepsGamesIndependent() {
        var tracker = SideSwitchPromptTracker()
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: true), .switchSides)
        // New game starts un-switched, then crosses again.
        XCTAssertNil(tracker.next(gameIndex: 1, hasSwitched: false))
        XCTAssertEqual(tracker.next(gameIndex: 1, hasSwitched: true), .switchSides)
    }

    func testResyncAfterDroppingAStalePromptPreventsABogusOppositePrompt() {
        var tracker = SideSwitchPromptTracker()
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: true), .switchSides)
        // The queued prompt went stale while the live flag is false again;
        // the user never saw the switch.
        tracker.resync(gameIndex: 0, to: false)
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: false))
    }
}
