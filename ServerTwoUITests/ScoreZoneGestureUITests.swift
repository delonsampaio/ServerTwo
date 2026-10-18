import XCTest

@MainActor
final class ScoreZoneGestureUITests: XCTestCase {
    /// Parses N out of a score zone label of the form
    /// "<name>, <N> points" (plus ", serving" for the serving team).
    private func score(of zone: XCUIElement) -> Int {
        let label = zone.label
        guard let comma = label.range(of: ", ") else { return -1 }
        let digits = label[comma.upperBound...].prefix(while: \.isNumber)
        return Int(digits) ?? -1
    }

    func testASlowPressStillScoresAndAQuickTapStillScores() throws {
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
        let teamBZone = app.buttons["scoreZone.teamB"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 3))
        XCTAssertTrue(teamBZone.waitForExistence(timeout: 3))
        func total() -> Int { score(of: teamAZone) + score(of: teamBZone) }
        XCTAssertEqual(total(), 0)

        // The serving team is random and a tap by the receiving team is only a
        // side-out (doubles: server one -> two -> side-out), so a few presses on
        // team A may be needed before it is serving. After at most three
        // presses A is serving AND has scored exactly one point. Each press is
        // 0.3s: longer than a quick tap, shorter than the 0.5s hold. If such a
        // press were dropped, nothing would ever score.
        var presses = 0
        while total() == 0 && presses < 3 {
            teamAZone.press(forDuration: 0.3)
            presses += 1
        }
        XCTAssertEqual(total(), 1, "0.3s presses never scored (dead zone): A=\(teamAZone.label) B=\(teamBZone.label)")
        XCTAssertEqual(score(of: teamAZone), 1)

        // Team A is now serving, so each further press by A scores.
        teamAZone.tap()
        XCTAssertEqual(score(of: teamAZone), 2, "a quick tap did not score: \(teamAZone.label)")
        teamAZone.press(forDuration: 0.3)
        XCTAssertEqual(score(of: teamAZone), 3, "a slow press did not score: \(teamAZone.label)")
        XCTAssertEqual(score(of: teamBZone), 0)
    }
}
