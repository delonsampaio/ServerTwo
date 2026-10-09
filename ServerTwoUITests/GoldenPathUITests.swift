import XCTest

final class GoldenPathUITests: XCTestCase {
    func testStartMatchScoreToWinAndAppearInHistory() throws {
        let app = XCUIApplication()
        // This test plays one full, uncapped game to 11 points — it's
        // testing the core gameplay loop, not paywall behavior (that's
        // PaywallTriggerUITests' job). The demo gate now lives at
        // match-start (ActiveMatchController.canStartNewMatch), not on
        // in-game scores, so no cap-related launch argument is needed here;
        // -UITest-ResetState alone clears match history, so this test's one
        // match is always within the default demoMatchLimit of 1.
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()

        dismissOnboardingIfPresented(app)

        // MatchSetupView is a Form (List-backed), which lazily renders rows —
        // "Flip Coin"/"Start Match" are below the fold on first layout and
        // genuinely not yet in the accessibility tree until scrolled into view.
        let flipCoinButton = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton, in: app)
        flipCoinButton.tap()

        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))

        // Tap "Team A" repeatedly — recordPoint(for:) means "Team A won
        // this rally," which the engine correctly turns into either a
        // score or a side-out depending on who was serving. At most one
        // extra tap is needed (if Team B won the opening coin flip) before
        // every subsequent tap scores, so 20 is a safe upper bound for a
        // win score of 11.
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        XCTAssertTrue(finishButton.waitForExistence(timeout: 2), "Match should finish well within 20 Team A points")

        finishButton.tap()
        // confirmationDialog buttons on this iOS runtime appear twice in the
        // accessibility tree (a wrapper Button containing an identical inner
        // Button, both exposing the same identifier/label) — .firstMatch
        // resolves the resulting ambiguous-match error deterministically.
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Team A vs Team B"].waitForExistence(timeout: 2))
    }
}
