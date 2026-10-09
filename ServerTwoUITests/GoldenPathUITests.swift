import XCTest

final class GoldenPathUITests: XCTestCase {
    func testStartMatchScoreToWinAndAppearInHistory() throws {
        let app = XCUIApplication()
        // This test plays a full, uncapped game to 11 points — it's testing
        // the core gameplay loop, not paywall behavior (that's
        // PaywallTriggerUITests' job), so the demo cap must be raised
        // STRICTLY ABOVE 11, not merely to 11: isPaywalled checks score >=
        // cap, so a cap of exactly 11 fires at the same instant the match's
        // win score of 11 is reached, racing the paywall sheet against the
        // finish-confirmation dialog for presentation. -UITest-ResetState
        // alone only resets proUnlocked to false; demoPointCap stays at its
        // production default of 5 unless -UITest-DemoPointCap is also
        // passed, which would otherwise make this test deterministically
        // hit the paywall at 5-0 every time regardless.
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoPointCap", "15"]
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

    private func dismissOnboardingIfPresented(_ app: XCUIApplication) {
        let doneButton = app.buttons["Done"]
        let skipButton = app.buttons["Skip"]
        if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        } else if skipButton.waitForExistence(timeout: 1) {
            skipButton.tap()
        }
    }

    /// MatchSetupView's Form lazily renders off-screen rows, so an element
    /// further down (e.g. "Flip Coin", "Start Match") may not exist in the
    /// accessibility tree until scrolled into view.
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var attempts = 0
        while !element.exists && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }
}
