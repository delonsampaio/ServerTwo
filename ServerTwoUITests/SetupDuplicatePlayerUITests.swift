import XCTest

@MainActor
final class SetupDuplicatePlayerUITests: XCTestCase {
    func testTheSameNameOnBothTeamsIsExplainedAndBlocksStartUntilItIsChanged() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)
        app.tabBars.buttons["Play"].tap()

        let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamAField, in: app)
        teamAField.tap()
        teamAField.typeText("Mike")
        let teamBField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBField.tap()
        teamBField.typeText("mike")

        let reason = app.staticTexts["Setup.DuplicatePlayerReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 2), "the repeated player should be explained")
        XCTAssertTrue(reason.label.contains("is listed more than once"))
        let startMatch = app.buttons["Start Match"]
        scrollUntilVisible(startMatch, in: app)
        XCTAssertFalse(startMatch.isEnabled, "Start Match must be disabled while a player is listed twice")

        // Telling them apart clears the line and re-enables Start Match.
        scrollUntilVisible(teamBField, in: app)
        teamBField.tap()
        teamBField.typeText(" S.")
        XCTAssertFalse(reason.waitForExistence(timeout: 1))
        scrollUntilVisible(startMatch, in: app)
        XCTAssertTrue(startMatch.isEnabled)
    }
}
