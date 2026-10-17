import XCTest

final class ScoreCorrectionUITests: XCTestCase {
    func testTwoScoreCorrectionGatesSaveOnReachabilityAndAppliesBothScoresAtOnce() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Start a match with default rules (side-out, 11 points, win by 2); names
        // stay blank so the Team A / Team B fallback applies.
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
        let teamBZone = app.buttons["scoreZone.teamB"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 3))

        // Long-press either score zone to open the two-score sheet.
        let save = app.buttons["ScoreCorrection.Save"]
        teamAZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))

        // The numerals expose the integer score as their accessibility value.
        let teamAScore = app.staticTexts["ScoreCorrection.TeamAScore"]
        let teamBScore = app.staticTexts["ScoreCorrection.TeamBScore"]
        let teamAIncrement = app.buttons["ScoreCorrection.TeamAIncrement"]
        let teamBIncrement = app.buttons["ScoreCorrection.TeamBIncrement"]

        // Starts at the current scores (0-0): nothing changed, so Save is off
        // and there is no hint.
        XCTAssertEqual(teamAScore.value as? String, "0")
        XCTAssertEqual(teamBScore.value as? String, "0")
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(app.staticTexts["ScoreCorrection.Hint"].exists)

        // A long press must open the sheet WITHOUT also scoring a point. The
        // final 12/11 assertions can't catch a stray point (the correction
        // sets absolute scores), so check it explicitly: cancel and look.
        app.buttons["ScoreCorrection.Cancel"].tap()
        let sheetGone = NSPredicate(format: "exists == false")
        expectation(for: sheetGone, evaluatedWith: save)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(teamAZone.label.contains("0 points"), "long press scored a stray point: \(teamAZone.label)")
        XCTAssertTrue(teamBZone.label.contains("0 points"), "long press scored a stray point: \(teamBZone.label)")

        // Reopen and continue.
        teamAZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))

        // Team A to 12 while B is 0: 12-0 can't happen in a game to 11 (win by 2).
        for _ in 0..<12 { teamAIncrement.tap() }
        XCTAssertTrue(app.staticTexts["ScoreCorrection.Hint"].waitForExistence(timeout: 2))
        XCTAssertFalse(save.isEnabled)

        // Team B to 11: 12-11 is a legitimate in-progress score — hint gone, Save on.
        // (Passing through 12-10, a completed final, is fine: nothing is saved yet.)
        for _ in 0..<11 { teamBIncrement.tap() }
        XCTAssertFalse(app.staticTexts["ScoreCorrection.Hint"].exists)
        XCTAssertTrue(save.isEnabled)

        save.tap()

        // The correction crosses the side-switch threshold on an in-progress
        // game, so the alert legitimately appears.
        // Asserted (not optional): this also proves the new `!match.isMatchOver`
        // guard does not suppress the alert for an in-progress game.
        let sideSwitchAlert = app.alerts["Side Switch"]
        XCTAssertTrue(sideSwitchAlert.waitForExistence(timeout: 5), "the correction crosses the side-switch threshold on a live game")
        sideSwitchAlert.buttons["OK"].tap()

        // Both scores applied at once, and the game did NOT end mid-edit.
        XCTAssertTrue(teamAZone.label.contains("12 points"), "got \(teamAZone.label)")
        XCTAssertTrue(teamBZone.label.contains("11 points"), "got \(teamBZone.label)")
        XCTAssertTrue(teamAZone.isEnabled)
        XCTAssertTrue(teamBZone.isEnabled)

        // Reopen from the OTHER zone: the sheet must start at the CURRENT scores
        // (a stale read is invisible at 0-0), and Save is off while unchanged.
        teamBZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertEqual(teamAScore.value as? String, "12")
        XCTAssertEqual(teamBScore.value as? String, "11")
        XCTAssertFalse(save.isEnabled)
        app.buttons["ScoreCorrection.Cancel"].tap()
    }
}
