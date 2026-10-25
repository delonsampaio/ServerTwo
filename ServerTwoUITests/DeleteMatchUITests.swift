import XCTest

@MainActor
final class DeleteMatchUITests: XCTestCase {
    /// Launches clean and quick-logs one match, saved as "Team A vs Team B"
    /// when no names are given (the shortest way to a completed match), or
    /// as "<A> vs <B>" with a saved player for each name.
    private func launchWithOneLoggedMatch(names: (teamA: String, teamB: String)? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        if let names {
            let singlesToggle = app.buttons["Singles"]
            if singlesToggle.exists { singlesToggle.tap() }
            let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
            scrollUntilVisible(teamAField, in: app)
            teamAField.tap()
            teamAField.typeText(names.teamA)
            let teamBField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
            teamBField.tap()
            teamBField.typeText(names.teamB)
        }
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
        let title = names.map { "\($0.teamA) vs \($0.teamB)" } ?? "Team A vs Team B"
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
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

    /// Screens that stay alive under other tabs keep their loaded matches. After
    /// a delete elsewhere they must not read the deleted match: Home, and a
    /// player's screen that was already open, both still hold it here.
    func testOtherScreensSurviveAMatchDeletedFromHistory() throws {
        let app = launchWithOneLoggedMatch(names: ("Delon", "Katie"))

        // Home loads its matches once, before this match existed; pull to
        // refresh so it holds the match when it is deleted.
        app.tabBars.buttons["Home"].tap()
        let lastMatchHeader = app.staticTexts["Last Match"]
        if !lastMatchHeader.waitForExistence(timeout: 2) {
            app.swipeDown()
        }
        XCTAssertTrue(lastMatchHeader.waitForExistence(timeout: 3))

        // Open Katie's screen first so it holds the match when it is deleted.
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()
        let katieRow = app.staticTexts["PlayerRow.Katie"]
        XCTAssertTrue(katieRow.waitForExistence(timeout: 3))
        katieRow.tap()
        XCTAssertTrue(app.navigationBars["Katie"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Delon vs Katie"].waitForExistence(timeout: 3))

        app.tabBars.buttons["History"].tap()
        let row = app.staticTexts["Delon vs Katie"]
        row.swipeLeft()
        let swipeDelete = app.buttons["Delete.Delon vs Katie"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 2))
        swipeDelete.tap()
        let alert = app.alerts["Delete this match?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This cannot be undone.")).firstMatch.exists)
        alert.buttons["ConfirmDeleteMatch"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No Matches Yet"].waitForExistence(timeout: 3))

        // Home shows its empty state.
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Play your first match to see it here."].waitForExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningForeground)

        // Katie's screen is still up, without the deleted match, and still works.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Katie"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Delon vs Katie"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let delonRow = app.staticTexts["PlayerRow.Delon"]
        XCTAssertTrue(delonRow.waitForExistence(timeout: 3))
        delonRow.tap()
        XCTAssertTrue(app.navigationBars["Delon"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
