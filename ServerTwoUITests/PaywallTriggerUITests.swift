import XCTest

final class PaywallTriggerUITests: XCTestCase {
    func testReachingDemoCapShowsPaywallAndUnlockingContinuesScoring() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoPointCap", "2"]
        app.launch()

        dismissOnboardingIfPresented(app)

        let flipCoinButton1 = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton1, in: app)
        flipCoinButton1.tap()

        let startMatchButton1 = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton1, in: app)
        startMatchButton1.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))

        // Up to 3 taps reaches the overridden 2-point cap, accounting for
        // one possible opening side-out if Team B won the coin flip.
        for _ in 0..<3 {
            teamAZone.tap()
        }

        let unlockButton = app.buttons["Unlock Pro — $1.99"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 2), "Paywall should appear once the demo cap is reached")
        unlockButton.tap()

        // Scoring should continue past the now-lifted cap, and the
        // paywall must not reappear on later points in this session.
        for _ in 0..<3 {
            teamAZone.tap()
        }
        XCTAssertFalse(app.buttons["Unlock Pro — $1.99"].exists, "Paywall should not reappear after unlocking")
    }

    func testDismissingPaywallWithoutUnlockingLeavesAPersistentWayToReopenIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoPointCap", "2"]
        app.launch()

        dismissOnboardingIfPresented(app)

        let flipCoinButton2 = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton2, in: app)
        flipCoinButton2.tap()

        let startMatchButton2 = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton2, in: app)
        startMatchButton2.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        for _ in 0..<3 {
            teamAZone.tap()
        }

        let notNowButton = app.buttons["Not Now"]
        XCTAssertTrue(notNowButton.waitForExistence(timeout: 2))
        notNowButton.tap()

        let reopenButton = app.buttons["Demo Limit Reached — Unlock to Continue"]
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 2), "A persistent way to reopen the paywall must remain after dismissing it without unlocking")
        reopenButton.tap()
        XCTAssertTrue(app.buttons["Unlock Pro — $1.99"].waitForExistence(timeout: 2))
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
