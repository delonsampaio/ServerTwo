import XCTest

@MainActor
final class OnboardingKeyboardUITests: XCTestCase {
    /// Typing a name must leave both the field and "Get Started" above the keyboard.
    func testTheNameFieldAndGetStartedStayAboveTheKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()

        let field = app.textFields["Your Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Onboarding should be presented")
        field.tap()
        field.typeText("Delon")

        let keyboard = app.keyboards.firstMatch
        try XCTSkipUnless(
            keyboard.waitForExistence(timeout: 3),
            "No software keyboard (the simulator is using the hardware keyboard), so there is nothing to measure"
        )
        let getStarted = app.buttons["Get Started"]
        // The scroll to the bottom waits for the keyboard's animation.
        let clear = NSPredicate { _, _ in
            field.frame.maxY <= keyboard.frame.minY && getStarted.frame.maxY <= keyboard.frame.minY
        }
        expectation(for: clear, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(getStarted.isHittable, "Get Started must be tappable while the keyboard is up")
    }
}
