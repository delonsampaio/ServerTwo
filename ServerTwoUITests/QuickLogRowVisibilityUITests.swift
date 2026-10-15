import XCTest

final class QuickLogRowVisibilityUITests: XCTestCase {
    func testTypingDigitsNeverPrematurelyRevealsTheNextRowAndEditingAnEarlierRowHidesButPreservesLaterRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        let bestOfThree = app.buttons["Best of 3"]
        scrollUntilVisible(bestOfThree, in: app)
        bestOfThree.tap()

        let quickLogButton = app.buttons["Log Final Score Instead"]
        scrollUntilVisible(quickLogButton, in: app)
        quickLogButton.tap()

        let game1TeamA = app.textFields["QuickLog.Game1.TeamAScore"]
        XCTAssertTrue(game1TeamA.waitForExistence(timeout: 2))
        game1TeamA.tap()
        game1TeamA.typeText("11")

        let game1TeamB = app.textFields["QuickLog.Game1.TeamBScore"]
        game1TeamB.tap()
        // Review Focus #1: Team A already shows "11" (committed on the
        // very first keystroke it had no partner score to be ambiguous
        // against). Typing "1" alone into Team B is now ambiguous — both
        // 11-1 and 11-13 are independently valid, decisive scores with
        // different winners — so it must wait out the short debounce
        // rather than flash Game 2 into existence on this one digit.
        game1TeamB.typeText("1")
        XCTAssertFalse(app.textFields["QuickLog.Game2.TeamAScore"].exists, "Game 2 must not appear while '1' alone is still ambiguous against Team A's 11")
        // Completing it to "13" is unambiguous (no further digit changes
        // the outcome) — this commits immediately, no "Done" tap needed.
        game1TeamB.typeText("3")
        let game2TeamA = app.textFields["QuickLog.Game2.TeamAScore"]
        XCTAssertTrue(game2TeamA.waitForExistence(timeout: 2), "Game 2 should appear as soon as Game 1's valid, unambiguous 11-13 score is typed")

        // Type something into Game 2 before going back to edit Game 1.
        game2TeamA.tap()
        game2TeamA.typeText("5")

        // Review Focus #2: editing Game 1 to an invalid score must hide
        // Game 2 immediately (an invalid/incomplete field always commits
        // at once, never debounced — there's nothing ambiguous about an
        // invalid score needing to "wait"), without discarding the "5"
        // already typed into it. Double-tap selects a short numeric
        // field's entire text on this keyboard, so typing immediately
        // after replaces it — if that doesn't hold on a real simulator,
        // substitute whatever text-replacement gesture does.
        game1TeamB.doubleTap()
        game1TeamB.typeText("10")  // 11-10 violates win-by-2 — invalid
        XCTAssertFalse(app.textFields["QuickLog.Game2.TeamAScore"].exists, "Game 2 should be hidden as soon as Game 1's score becomes invalid")

        // Fix Game 1 back to the valid 11-13 — Game 2 should reappear
        // with its "5" still there, untouched underneath. "13" is
        // multi-digit, so it's unambiguous and commits immediately too.
        game1TeamB.doubleTap()
        game1TeamB.typeText("13")

        let game2TeamAAgain = app.textFields["QuickLog.Game2.TeamAScore"]
        XCTAssertTrue(game2TeamAAgain.waitForExistence(timeout: 2))
        XCTAssertEqual(game2TeamAAgain.value as? String, "5", "Game 2's previously typed text must survive being hidden and shown again")
    }
}
