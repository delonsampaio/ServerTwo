import XCTest

/// Doubles court positions on the score cards. The R/L badges sit inside the
/// card's single accessibility element, so everything here asserts on the
/// zone's VoiceOver label, which carries the same words.
@MainActor
final class CourtPositionsUITests: XCTestCase {
    private func typeName(_ app: XCUIApplication, field identifier: String, _ text: String) {
        let field = app.textFields.matching(identifier: identifier).firstMatch
        scrollUntilVisible(field, in: app)
        field.tap()
        field.typeText(text)
    }

    /// Setup -> coin flip -> live scoring. `singles` taps the Singles toggle first.
    private func startMatch(_ app: XCUIApplication, singles: Bool = false) {
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)
        app.tabBars.buttons["Play"].tap()
        if singles {
            let toggle = app.buttons["Singles"]
            scrollUntilVisible(toggle, in: app)
            toggle.tap()
            typeName(app, field: "Team A Player Name", "Delon")
            typeName(app, field: "Team B Player Name", "Fred")
        } else {
            typeName(app, field: "Team A Player Name", "Delon")
            typeName(app, field: "Team A Player 2 Name", "Katie")
            typeName(app, field: "Team B Player Name", "Fred")
            typeName(app, field: "Team B Player 2 Name", "Gina")
        }
        let start = app.buttons["Start Match"]
        scrollUntilVisible(start, in: app)
        start.tap()
        let flip = app.buttons["Flip Coin"]
        XCTAssertTrue(flip.waitForExistence(timeout: 3))
        flip.tap()
        let begin = app.buttons["Begin Match"]
        XCTAssertTrue(begin.waitForExistence(timeout: 3))
        begin.tap()
        XCTAssertTrue(app.buttons["scoreZone.teamA"].waitForExistence(timeout: 3))
    }

    func testDoublesCardsShowPartnerPositionsAndFlipWhenTheTeamScores() throws {
        let app = XCUIApplication()
        startMatch(app)
        let teamA = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamA.label.contains("0 points"), teamA.label)
        XCTAssertTrue(teamA.label.contains("Delon on the right, Katie on the left"), teamA.label)
        XCTAssertTrue(app.buttons["scoreZone.teamB"].label.contains("Fred on the right, Gina on the left"))

        // Whoever serves first, Team A scores within two taps: a tap on the
        // receiving card is a side out (or second server) first.
        for _ in 0..<4 where !teamA.label.contains("1 points") {
            teamA.tap()
        }
        XCTAssertTrue(teamA.label.contains("1 points"), teamA.label)
        XCTAssertTrue(teamA.label.contains("Katie on the right, Delon on the left"), teamA.label)
        XCTAssertTrue(app.buttons["scoreZone.teamB"].label.contains("Fred on the right, Gina on the left"),
                      "the other team did not score, so it does not move")

        // Swap in the correction sheet, change no digits, Save.
        teamA.press(forDuration: 1.0)
        let save = app.buttons["ScoreCorrection.Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertFalse(save.isEnabled, "nothing changed yet")
        let preview = app.staticTexts["ScoreCorrection.TeamAPositionsPreview"]
        XCTAssertEqual(preview.label, "Delon L · Katie R")
        app.buttons["ScoreCorrection.TeamASwapPositions"].tap()
        XCTAssertEqual(preview.label, "Delon R · Katie L")
        XCTAssertTrue(save.isEnabled, "a swap alone enables Save")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 3))

        XCTAssertTrue(teamA.label.contains("1 points"), "a swap must not change the score: \(teamA.label)")
        XCTAssertTrue(teamA.label.contains("Delon on the right, Katie on the left"), teamA.label)
    }

    func testCancelDiscardsASwap() throws {
        let app = XCUIApplication()
        startMatch(app)
        let teamA = app.buttons["scoreZone.teamA"]
        teamA.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["ScoreCorrection.Save"].waitForExistence(timeout: 3))
        app.buttons["ScoreCorrection.TeamASwapPositions"].tap()
        app.buttons["ScoreCorrection.Cancel"].tap()
        XCTAssertTrue(app.buttons["ScoreCorrection.Save"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(teamA.label.contains("Delon on the right, Katie on the left"), teamA.label)
    }

    func testSinglesShowsNoPositions() throws {
        let app = XCUIApplication()
        startMatch(app, singles: true)
        let label = app.buttons["scoreZone.teamA"].label
        XCTAssertTrue(label.contains("0 points"), label)
        XCTAssertFalse(label.contains("on the right"), label)
        XCTAssertFalse(label.contains("on the left"), label)
    }
}
