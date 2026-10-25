import XCTest

@MainActor
final class DeleteMatchUITests: XCTestCase {
    /// Launches clean and quick-logs one match with blank names (the shortest
    /// way to a completed match), saved as "Team A vs Team B".
    private func launchWithOneLoggedMatch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

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
        XCTAssertTrue(app.staticTexts["Team A vs Team B"].waitForExistence(timeout: 3))
        return app
    }

    func testSwipeDeleteFromHistoryAsksFirstThenRemovesTheRow() throws {
        let app = launchWithOneLoggedMatch()
        let row = app.staticTexts["Team A vs Team B"]

        row.swipeLeft()
        let swipeDelete = app.buttons["Delete.Team A vs Team B"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 2))
        swipeDelete.tap()

        // Cancel leaves everything as it was.
        let alert = app.alerts["Delete this match?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Team A vs Team B")).firstMatch.exists)
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(row.exists)
        XCTAssertFalse(app.staticTexts["No Matches Yet"].exists)

        // Delete confirms: the row goes and History shows its empty state.
        row.swipeLeft()
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 2))
        swipeDelete.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        alert.buttons["ConfirmDeleteMatch"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["No Matches Yet"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Team A vs Team B"].exists)
    }

    func testDeleteMatchFromDetailCancelKeepsItAndConfirmReturnsToHistory() throws {
        let app = launchWithOneLoggedMatch()
        app.staticTexts["Team A vs Team B"].tap()

        let deleteButton = app.buttons["Delete Match"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        let alert = app.alerts["Delete this match?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
        // Still on the same Match Detail, nothing changed.
        XCTAssertTrue(app.navigationBars["Match Detail"].exists)
        XCTAssertTrue(deleteButton.exists)

        deleteButton.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        alert.buttons["ConfirmDeleteMatch"].firstMatch.tap()

        // Back on History, without the row, showing the empty state.
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No Matches Yet"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Team A vs Team B"].exists)
        XCTAssertFalse(app.navigationBars["Match Detail"].exists)
    }
}
