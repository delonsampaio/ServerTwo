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

    func testEngineWinnerBeatsTheScoreFallback() {
        // A rally-scoring game can be "won" by the engine's rules without the
        // higher score being the deciding factor in our fallback; trust it.
        XCTAssertEqual(ScoringPromptSheet.resolvedWinner(.teamB, teamAScore: 11, teamBScore: 9), .teamB)
        XCTAssertEqual(ScoringPromptSheet.resolvedWinner(nil, teamAScore: 5, teamBScore: 5), nil)
    }

    func testStartNextGameButtonNumbersTheFollowingGame() {
        XCTAssertEqual(ScoringPromptSheet.startNextGameTitle(afterGame: 1), "Start Game 2")
        XCTAssertEqual(ScoringPromptSheet.startNextGameTitle(afterGame: 4), "Start Game 5")
    }

    func testGamesTallyLine() {
        XCTAssertEqual(ScoringPromptSheet.gamesTallyLine(teamAGames: 1, teamBGames: 0), "Games 1 – 0")
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
        XCTAssertEqual(ScoringPrompt.sideSwitch(teamAName: "A", teamBName: "B", teamAScore: 1, teamBScore: 0).id, "sideSwitch")
        XCTAssertEqual(
            ScoringPrompt.gameOver(
                gameNumber: 1, teamAName: "A", teamBName: "B", teamAScore: 11, teamBScore: 0,
                winner: .teamA, teamAGames: 1, teamBGames: 0
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
}
