import XCTest

final class PaywallTriggerUITests: XCTestCase {
    /// Plays and finishes one full match (flip coin → start → score to an
    /// 11-point win → confirm finish) from a fresh MatchSetupView, leaving
    /// the app back at MatchSetupView with `match == nil`. Mirrors
    /// GoldenPathUITests' sequence; not shared via a helper since the two
    /// files' existing minor duplication is already a tracked, deferred
    /// finding — adding a third copy here doesn't change that calculus.
    private func playAndFinishOneMatch(in app: XCUIApplication) {
        let flipCoinButton = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton, in: app)
        flipCoinButton.tap()

        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))

        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        XCTAssertTrue(finishButton.waitForExistence(timeout: 2), "Match should finish well within 20 Team A points")

        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()
    }

    func testStartingASecondMatchAfterUsingTheFreeDemoMatchShowsThePaywallAndUnlockingLetsItStart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoMatchLimit", "1"]
        app.launch()

        dismissOnboardingIfPresented(app)

        // Use up the one free demo match. The demo gate now lives at
        // match-start (ActiveMatchController.canStartNewMatch), not on
        // in-game scores, so this match plays uninterrupted to a real
        // finish — that full loop is the whole point of the one-free-match
        // design: let a free user see history/the recap card before paying.
        playAndFinishOneMatch(in: app)

        // Back at a fresh MatchSetupView (match cleared by finishMatch()).
        // Flipping again is required: MatchSetupView's @State resets when
        // RootTabView swaps it back in after ScoringView tears down.
        let flipCoinButton2 = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton2, in: app)
        flipCoinButton2.tap()

        let startMatchButton2 = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton2, in: app)
        startMatchButton2.tap()

        let unlockButton = app.buttons["Unlock Pro — $1.99"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 2), "Starting a second match should show the paywall once the free demo match is used up")
        XCTAssertFalse(app.buttons["scoreZone.teamA"].exists, "The paywall should block the match from actually starting")

        unlockButton.tap()

        // Unlocking dismisses the paywall sheet but doesn't auto-start the
        // match — tapping "Start Match" again should now succeed.
        scrollUntilVisible(startMatchButton2, in: app)
        startMatchButton2.tap()
        XCTAssertTrue(app.buttons["scoreZone.teamA"].waitForExistence(timeout: 2), "Start Match should succeed once Pro is unlocked")
    }

    func testDismissingPaywallWithoutUnlockingLeavesMatchSetupUsableAndReshowsThePaywallOnRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoMatchLimit", "1"]
        app.launch()

        dismissOnboardingIfPresented(app)

        playAndFinishOneMatch(in: app)

        let flipCoinButton2 = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton2, in: app)
        flipCoinButton2.tap()

        let startMatchButton2 = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton2, in: app)
        startMatchButton2.tap()

        let notNowButton = app.buttons["Not Now"]
        XCTAssertTrue(notNowButton.waitForExistence(timeout: 2))
        notNowButton.tap()

        // Dismissing without unlocking must leave MatchSetupView usable
        // (not accidentally started a match) and must re-show the paywall
        // on a retry, since the gate re-checks on every tap rather than
        // only once.
        XCTAssertFalse(app.buttons["scoreZone.teamA"].exists)
        XCTAssertTrue(startMatchButton2.exists)
        startMatchButton2.tap()
        XCTAssertTrue(app.buttons["Unlock Pro — $1.99"].waitForExistence(timeout: 2), "The paywall should reappear on a retry")
    }
}
