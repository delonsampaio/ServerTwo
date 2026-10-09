import XCTest

/// Shared XCUITest helpers. These were previously duplicated verbatim as
/// `private` copies in both `GoldenPathUITests` and `PaywallTriggerUITests`;
/// an `XCTestCase` extension keeps every existing call site unchanged.
extension XCTestCase {
    /// Dismisses the onboarding sheet if this launch presented it, so a test
    /// doesn't depend on whether a previous run already marked it seen.
    func dismissOnboardingIfPresented(_ app: XCUIApplication) {
        let doneButton = app.buttons["Done"]
        let skipButton = app.buttons["Skip"]
        if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        } else if skipButton.waitForExistence(timeout: 1) {
            skipButton.tap()
        }
    }

    /// `MatchSetupView`'s Form lazily renders off-screen rows, so an element
    /// further down (e.g. "Flip Coin", "Start Match") may not exist in the
    /// accessibility tree until scrolled into view.
    ///
    /// Asserts on the way out: a genuinely-missing element otherwise surfaced
    /// as a confusing failure at the caller's later `.tap()` rather than here.
    /// `file`/`line` default to the call site, so the failure is reported at
    /// the scroll site instead of inside this helper.
    func scrollUntilVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var attempts = 0
        while !element.exists && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(
            element.exists,
            "Element never became visible after \(maxSwipes) swipes",
            file: file,
            line: line
        )
    }
}
