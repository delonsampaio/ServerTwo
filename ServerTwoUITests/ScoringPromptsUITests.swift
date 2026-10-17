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

        let save = app.buttons["ScoreCorrection.Save"]
        let teamAIncrement = app.buttons["ScoreCorrection.TeamAIncrement"]
        let dismissButton = app.buttons["Prompt.Dismiss"]

        // The mid-game change of ends applies only in the last game of the
        // format, so reaching 6 in game 1 of a best of 3 must NOT show the
        // Switch Sides sheet.
        teamAZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        for _ in 0..<6 { teamAIncrement.tap() }
        save.tap()
        XCTAssertFalse(dismissButton.waitForExistence(timeout: 2), "no Switch Sides sheet in game 1 of a best of 3")

        // Correct from 6-0 to 11-0: a finished game, so Save ends game 1.
        teamAZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        for _ in 0..<5 { teamAIncrement.tap() }
        save.tap()

        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5), "Game Over prompt never appeared after the correction sheet closed")
        XCTAssertTrue(app.otherElements["Prompt.GameOver"].exists)
        XCTAssertTrue(app.staticTexts["Game 1 goes to Team A"].exists)
        XCTAssertTrue(app.staticTexts["Games 1 – 0"].exists)
        XCTAssertTrue(app.staticTexts["Next game starts at 0-0."].exists)
        XCTAssertTrue(app.staticTexts["Teams change ends."].exists)
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
        // Both the match and its Cancel prompt must be gone.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: teamAZone)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.otherElements["Prompt.CancelMatch"])
        waitForExpectations(timeout: 5)
        scrollUntilVisible(app.buttons["Start Match"], in: app)
    }

    /// Undo restores the earlier game state including the side-switch flag, so
    /// crossing the threshold again must prompt again (and undoing below it
    /// must say the teams switch back) — not silently flip the court.
    func testSideSwitchPromptsAgainAfterUndoAndRecrossing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
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
        let save = app.buttons["ScoreCorrection.Save"]
        let teamAIncrement = app.buttons["ScoreCorrection.TeamAIncrement"]
        let dismissButton = app.buttons["Prompt.Dismiss"]

        func dismissPrompt(titled title: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(dismissButton.waitForExistence(timeout: 5), "no \(title) prompt", file: file, line: line)
            XCTAssertTrue(app.staticTexts[title].exists, "expected \(title)", file: file, line: line)
            dismissButton.tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: dismissButton)
            waitForExpectations(timeout: 3)
        }

        func correctToSixNil() {
            teamAZone.press(forDuration: 1.0)
            XCTAssertTrue(save.waitForExistence(timeout: 3))
            for _ in 0..<6 { teamAIncrement.tap() }
            save.tap()
        }

        correctToSixNil()
        dismissPrompt(titled: "Switch Sides")

        app.buttons["Undo"].tap()
        dismissPrompt(titled: "Switch Back")

        correctToSixNil()
        dismissPrompt(titled: "Switch Sides")
        // Give a duplicate presented from an onDismiss time to show up.
        sleep(1)
        XCTAssertFalse(dismissButton.exists, "exactly one prompt per crossing")
    }
}
