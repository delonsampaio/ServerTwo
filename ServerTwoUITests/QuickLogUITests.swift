import XCTest

@MainActor
final class QuickLogUITests: XCTestCase {
    func testLoggingAFinalScoreSavesTheMatchWithNoPointLogAndResetsSetupFields() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamAField, in: app)
        app.swipeUp()
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }

        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText("Delon")

        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText("Katie")

        let quickLogButton = app.buttons["Log Final Score Instead"]
        scrollUntilVisible(quickLogButton, in: app)
        quickLogButton.tap()

        let game1TeamA = app.textFields["QuickLog.Game1.TeamAScore"]
        XCTAssertTrue(game1TeamA.waitForExistence(timeout: 2))
        game1TeamA.tap()
        game1TeamA.typeText("11")

        let game1TeamB = app.textFields["QuickLog.Game1.TeamBScore"]
        game1TeamB.tap()
        game1TeamB.typeText("7")

        // "7" is unambiguous against Team A's already-committed "11", so
        // typing it commits immediately — Save is already enabled before
        // this tap. "Done" here just dismisses the keyboard before
        // interacting with the nav bar, matching realistic use. Tapping it
        // is harmless (it only re-commits the same already-committed
        // scores) and nothing below depends on it: Save would be enabled
        // without it.
        app.buttons["QuickLog.Done"].tap()

        // Default match format is Best of 1 — committing Game 1 alone
        // decides the match, so no Game 2 row should appear, and Save
        // should become enabled.
        XCTAssertFalse(app.textFields["QuickLog.Game2.TeamAScore"].exists)
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        // MatchSetupView's own fields are reset after a successful save.
        // The Form may still be scrolled down to where "Log Final Score
        // Instead" was (this Form lazily renders off-screen rows — see
        // XCUIApplication+TestHelpers' note on scrollUntilVisible), so
        // scroll back toward the top before looking for "Team A Player
        // Name" again.
        for _ in 0..<6 { app.swipeDown() }
        let teamATextFieldAfterSave = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        XCTAssertTrue(teamATextFieldAfterSave.waitForExistence(timeout: 2))
        // An empty field reports either "" or its placeholder as `value`
        // depending on the simulator/iOS version (this environment reports
        // ""), so accept either — what matters is "Delon" is gone.
        XCTAssertTrue(
            ["", "Player Name"].contains(teamATextFieldAfterSave.value as? String ?? "<nil>"),
            "Team A's field should be empty again, got \(String(describing: teamATextFieldAfterSave.value))"
        )

        // The match shows up in History with the entered score, and
        // MatchDetailView has no point-by-point log for it (since
        // GameRecord.points stays empty for a quick-logged game).
        app.tabBars.buttons["History"].tap()
        let matchRow = app.staticTexts["Delon vs Katie"]
        XCTAssertTrue(matchRow.waitForExistence(timeout: 2))
        matchRow.tap()

        XCTAssertTrue(app.staticTexts["Game 1"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["11"].exists, "the logged Team A score should show on the detail screen")
        XCTAssertTrue(app.staticTexts["7"].exists, "the logged Team B score should show on the detail screen")
        XCTAssertFalse(app.staticTexts["Delon scored"].exists, "a quick-logged game has no point-by-point log to show")
        XCTAssertFalse(app.staticTexts["Katie scored"].exists)
    }

    func testBlankTeamNamesFallBackToTeamAAndTeamB() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Leave both team name fields blank — don't type anything.
        app.tabBars.buttons["Play"].tap()
        let quickLogButton = app.buttons["Log Final Score Instead"]
        scrollUntilVisible(quickLogButton, in: app)
        quickLogButton.tap()

        let game1TeamA = app.textFields["QuickLog.Game1.TeamAScore"]
        XCTAssertTrue(game1TeamA.waitForExistence(timeout: 2))
        game1TeamA.tap()
        game1TeamA.typeText("11")
        let game1TeamB = app.textFields["QuickLog.Game1.TeamBScore"]
        game1TeamB.tap()
        game1TeamB.typeText("7")
        app.buttons["QuickLog.Done"].tap()
        app.buttons["Save"].tap()

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Team A vs Team B"].waitForExistence(timeout: 2), "blank team names should fall back to Team A/Team B, matching a live match's own fallback")
    }

    func testQuickLogButtonIsGatedBehindThePaywallLikeStartMatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoMatchLimit", "1"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamAField, in: app)
        app.swipeUp()
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }

        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText("Delon")
        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText("Katie")

        // Use up the one free demo match via Quick Log itself.
        let quickLogButton = app.buttons["Log Final Score Instead"]
        scrollUntilVisible(quickLogButton, in: app)
        quickLogButton.tap()
        let game1TeamA = app.textFields["QuickLog.Game1.TeamAScore"]
        XCTAssertTrue(game1TeamA.waitForExistence(timeout: 2))
        game1TeamA.tap()
        game1TeamA.typeText("11")
        let game1TeamB = app.textFields["QuickLog.Game1.TeamBScore"]
        game1TeamB.tap()
        game1TeamB.typeText("7")
        app.buttons["QuickLog.Done"].tap()
        app.buttons["Save"].tap()

        // A second Quick Log attempt should hit the same paywall
        // "Start Match" would, not open the sheet.
        app.tabBars.buttons["Play"].tap()
        let quickLogButton2 = app.buttons["Log Final Score Instead"]
        scrollUntilVisible(quickLogButton2, in: app)
        quickLogButton2.tap()

        XCTAssertTrue(app.buttons["Unlock Pro — $1.99"].waitForExistence(timeout: 2), "Quick Log should hit the same demo-limit paywall Start Match does")
        XCTAssertFalse(app.textFields["QuickLog.Game1.TeamAScore"].exists, "the paywall should block the sheet from ever opening")
    }
}
