import XCTest

final class HistoryFilterUITests: XCTestCase {
    func testFilteringHistoryByPlayerShowsOnlyTheirMatches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoMatchLimit", "2"]
        app.launch()
        dismissOnboardingIfPresented(app)

        playSinglesMatch(app, teamA: "Delon", teamB: "Katie")
        playSinglesMatch(app, teamA: "Delon", teamB: "Mike")

        app.tabBars.buttons["History"].tap()
        let delonVsKatie = app.staticTexts["Delon vs Katie"]
        let delonVsMike = app.staticTexts["Delon vs Mike"]
        XCTAssertTrue(delonVsKatie.waitForExistence(timeout: 2))
        XCTAssertTrue(delonVsMike.exists, "Both matches should show with no filter applied")

        app.buttons["History Filter Menu"].tap()
        app.buttons["Katie"].tap()

        XCTAssertTrue(delonVsKatie.waitForExistence(timeout: 2), "The Katie match should still show when filtered to Katie")
        XCTAssertFalse(delonVsMike.exists, "The Mike match should be hidden when filtered to Katie")

        app.buttons["History Filter Menu"].tap()
        app.buttons["All Matches"].tap()

        XCTAssertTrue(delonVsKatie.waitForExistence(timeout: 2))
        XCTAssertTrue(delonVsMike.exists, "Both matches should return once the filter is cleared")
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
