import XCTest

/// Game Over and Cancel Match are sheets queued behind the Correct Score
/// sheet, not system alerts. The correction path is the risky one: its Save
/// completes the game while the correction sheet is still on screen, so the
/// Game Over prompt must wait for that sheet's dismissal and then appear.
final class ScoringPromptsUITests: XCTestCase {
    func testGameOverAfterCorrectionThenCancelMatchPrompt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Best of 3 so finishing game 1 does not end the match. Names stay
        // blank, so the Team A / Team B fallback applies.
        app.tabBars.buttons["Play"].tap()
        let bestOfThree = app.buttons["Best of 3"]
        scrollUntilVisible(bestOfThree, in: app)
        bestOfThree.tap()
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()
        let flipCoinButton = app.buttons["Flip Coin"]
        XCTAssertTrue(flipCoinButton.waitForExistence(timeout: 3))
        flipCoinButton.tap()
        let beginMatchButton = app.buttons["Begin Match"]
        XCTAssertTrue(beginMatchButton.waitForExistence(timeout: 3))
        beginMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 3))

        // Correct to 11-0: a finished game, so Save ends game 1.
        let save = app.buttons["ScoreCorrection.Save"]
        teamAZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        let teamAIncrement = app.buttons["ScoreCorrection.TeamAIncrement"]
        for _ in 0..<11 { teamAIncrement.tap() }
        save.tap()

        let dismissButton = app.buttons["Prompt.Dismiss"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5), "Game Over prompt never appeared after the correction sheet closed")
        XCTAssertTrue(app.otherElements["Prompt.GameOver"].exists)
        XCTAssertTrue(app.staticTexts["Game 1 goes to Team A"].exists)
        XCTAssertTrue(app.staticTexts["Games 1 – 0"].exists)
        XCTAssertTrue(app.staticTexts["Next game starts at 0-0."].exists)
        XCTAssertEqual(dismissButton.label, "Start Game 2")
        dismissButton.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: dismissButton)
        waitForExpectations(timeout: 3)

        // Cancel Match: Keep Playing leaves the match alone.
        let toolbarCancel = app.buttons["Cancel Match"]
        toolbarCancel.tap()
        let keepPlaying = app.buttons["Prompt.KeepPlaying"]
        XCTAssertTrue(keepPlaying.waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["Prompt.CancelMatch"].exists)
        XCTAssertTrue(app.staticTexts["Cancel this match?"].exists)
        XCTAssertTrue(app.staticTexts["Team A vs Team B"].exists)
        XCTAssertTrue(app.staticTexts["Games 1 – 0, current game 0 – 0"].exists)
        keepPlaying.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: keepPlaying)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(teamAZone.exists, "Keep Playing must leave the match running")

        // Cancel Match for real returns to the setup screen.
        toolbarCancel.tap()
        let confirm = app.buttons["Confirm Cancel Match"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: teamAZone)
        waitForExpectations(timeout: 5)
        scrollUntilVisible(app.buttons["Start Match"], in: app)
    }
}
