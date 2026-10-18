import XCTest

@MainActor
final class ChemistryRowsUITests: XCTestCase {
    func testChemistryRowsAppearForOtherPlayerWhenMeIsSetAndOmittedOnOwnProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        playSinglesMatch(app, teamA: "Delon", teamB: "Katie")

        // Set "Delon" as Me via Manage Players.
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()
        app.buttons["SetMe.Delon"].tap()

        // Viewing Katie's profile (not Me) — chemistry rows should appear.
        app.staticTexts["PlayerRow.Katie"].tap()
        XCTAssertTrue(app.staticTexts["As Your Opponent"].waitForExistence(timeout: 3))

        app.navigationBars.buttons.firstMatch.tap()

        // Viewing Delon's own profile (Me) — chemistry rows must NOT appear.
        app.staticTexts["PlayerRow.Delon"].tap()
        XCTAssertTrue(app.navigationBars["Delon"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["As Your Opponent"].exists)
        XCTAssertFalse(app.staticTexts["As Your Partner"].exists)
    }

    private func playSinglesMatch(_ app: XCUIApplication, teamA: String, teamB: String) {
        app.tabBars.buttons["Play"].tap()
        let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamAField, in: app)
        app.swipeUp()
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }

        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText(teamA)

        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText(teamB)

        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()

        let flipCoinButton = app.buttons["Flip Coin"]
        XCTAssertTrue(flipCoinButton.waitForExistence(timeout: 2))
        flipCoinButton.tap()
        let beginMatchButton = app.buttons["Begin Match"]
        XCTAssertTrue(beginMatchButton.waitForExistence(timeout: 2))
        beginMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()
    }
}
