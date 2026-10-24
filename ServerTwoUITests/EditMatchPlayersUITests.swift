import XCTest

@MainActor
final class EditMatchPlayersUITests: XCTestCase {
    func testEditingAQuickLoggedMatchesPlayersUpdatesTheDetailAndTheHistoryRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // The shortest way to get a completed match: quick-log one with both
        // names left blank, so it is saved as "Team A vs Team B".
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
        let originalRow = app.staticTexts["Team A vs Team B"]
        XCTAssertTrue(originalRow.waitForExistence(timeout: 2))
        originalRow.tap()

        let editButton = app.buttons["Edit Players"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 2))
        editButton.tap()

        let teamASlot = app.textFields["EditPlayers.TeamA.Slot1"]
        XCTAssertTrue(teamASlot.waitForExistence(timeout: 2))
        teamASlot.tap()
        teamASlot.typeText("Zed")
        let teamBSlot = app.textFields["EditPlayers.TeamB.Slot1"]
        teamBSlot.tap()
        teamBSlot.typeText("Quinn")

        // The keyboard covers Save, so dismiss it first.
        teamBSlot.typeText("\n")
        let save = app.buttons["EditPlayers.Save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // The detail screen already shows the new names...
        XCTAssertTrue(app.staticTexts["Zed vs Quinn"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Team A vs Team B"].exists)

        // ...and so does the History row once we pop back (no pull-to-refresh),
        // with the old one gone.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Zed vs Quinn"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Team A vs Team B"].exists)
    }
}
