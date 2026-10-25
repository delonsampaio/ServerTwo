import XCTest

/// Reaching the Pro purchase from Settings and Home. The `-UITest-` launch
/// argument swaps StoreKit for a fake store (price "$1.99" at once, purchase
/// unlocks, restore finds nothing), so these never touch the App Store.
@MainActor
final class ProPurchaseUITests: XCTestCase {
    private static let nothingToRestore = "No previous purchase of Server Two Pro was found for this Apple Account."

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)
        // -UITest-ResetState can re-present onboarding just after the first
        // dismissal (it resets `hasSeenOnboarding` in a launch task), so check again.
        dismissOnboardingIfPresented(app)
        // A previous test's unfinished match makes the app start on the Play
        // tab (the tab is chosen before -UITest-ResetState clears it).
        app.tabBars.buttons["Home"].tap()
        return app
    }

    func testUnlockingFromSettingsDismissesThePaywallAndShowsUnlocked() throws {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()

        let unlockRow = app.buttons["Settings.UnlockPro"]
        XCTAssertTrue(unlockRow.waitForExistence(timeout: 3), "Settings always offers the purchase while locked")
        unlockRow.tap()

        let unlockButton = app.buttons["Paywall.UnlockPro"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 3))
        XCTAssertTrue(unlockButton.label.contains("$1.99"), "the button shows the store's price: \(unlockButton.label)")
        unlockButton.tap()

        XCTAssertTrue(unlockButton.waitForNonExistence(timeout: 5), "The paywall should dismiss itself once Pro is unlocked")
        XCTAssertTrue(app.staticTexts["Server Two Pro: Unlocked"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Settings.UnlockPro"].exists)
    }

    func testRestoreWithNothingToRestoreShowsAMessageInSettingsAndOnThePaywall() throws {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()

        let restoreRow = app.buttons["Settings.Restore"]
        XCTAssertTrue(restoreRow.waitForExistence(timeout: 3))
        restoreRow.tap()
        XCTAssertTrue(
            app.staticTexts[Self.nothingToRestore].waitForExistence(timeout: 3),
            "Restore should explain that nothing was found"
        )

        app.buttons["Settings.UnlockPro"].tap()
        let paywallRestore = app.buttons["Paywall.Restore"]
        XCTAssertTrue(paywallRestore.waitForExistence(timeout: 3))
        paywallRestore.tap()
        XCTAssertTrue(app.staticTexts["Paywall.RestoreResult"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["Paywall.RestoreResult"].label, Self.nothingToRestore)
    }

    func testAFreshInstallReachesThePurchaseFromHomeInOneTap() throws {
        let app = launch()
        let banner = app.buttons["Home Unlock Pro Banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 3), "Home's empty state offers the upgrade while locked")
        XCTAssertTrue(banner.label.contains("$1.99"), "the banner shows the store's price: \(banner.label)")
        banner.tap()
        XCTAssertTrue(app.buttons["Paywall.UnlockPro"].waitForExistence(timeout: 3))
    }
}
