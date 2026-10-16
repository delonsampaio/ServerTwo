import XCTest

final class QuickLogRowVisibilityUITests: XCTestCase {
    func testTypingDigitsNeverPrematurelyRevealsTheNextRowAndEditingAnEarlierRowHidesButPreservesLaterRows() throws {
        // A 3s debounce makes the "Game 2 must not appear yet" check below
        // robust against a slow/parallel simulator: the ambiguous "1" can't
        // commit inside this test's window unless the wiring is wrong.
        let app = launchQuickLogBestOfThree(debounceMs: 3000)

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

        // A 3rd digit is rejected by the 2-character cap; the field must
        // keep DISPLAYING "13" (not "135") so the screen matches what Save
        // would persist.
        game1TeamB.typeText("5")
        XCTAssertEqual(game1TeamB.value as? String, "13", "a rejected 3rd digit must not stay visible in the field")

        // Type something into Game 2 before going back to edit Game 1.
        game2TeamA.tap()
        game2TeamA.typeText("5")

        // Review Focus #2: editing Game 1 to an invalid score must hide
        // Game 2 immediately (an invalid/incomplete field always commits
        // at once, never debounced — there's nothing ambiguous about an
        // invalid score needing to "wait"), without discarding the "5"
        // already typed into it.
        replaceText(of: game1TeamB, with: "10")  // 11-10 violates win-by-2 — invalid
        XCTAssertFalse(app.textFields["QuickLog.Game2.TeamAScore"].exists, "Game 2 should be hidden as soon as Game 1's score becomes invalid")

        // Fix Game 1 back to the valid 11-13 — Game 2 should reappear
        // with its "5" still there, untouched underneath. "13" is
        // multi-digit, so it's unambiguous and commits immediately too.
        replaceText(of: game1TeamB, with: "13")

        let game2TeamAAgain = app.textFields["QuickLog.Game2.TeamAScore"]
        XCTAssertTrue(game2TeamAAgain.waitForExistence(timeout: 2))
        XCTAssertEqual(game2TeamAAgain.value as? String, "5", "Game 2's previously typed text must survive being hidden and shown again")
    }

    /// Proves the deferred (debounced) commit actually fires: "1" alone
    /// against Team A's 11 is ambiguous, but once the short debounce
    /// elapses it must commit as 11-1 (a valid decisive score) and reveal
    /// Game 2 with no further typing.
    func testAmbiguousSingleDigitCommitsAfterTheDebounceElapses() throws {
        let app = launchQuickLogBestOfThree(debounceMs: 300)

        let game1TeamA = app.textFields["QuickLog.Game1.TeamAScore"]
        XCTAssertTrue(game1TeamA.waitForExistence(timeout: 2))
        game1TeamA.tap()
        game1TeamA.typeText("11")

        let game1TeamB = app.textFields["QuickLog.Game1.TeamBScore"]
        game1TeamB.tap()
        game1TeamB.typeText("1")

        XCTAssertTrue(
            app.textFields["QuickLog.Game2.TeamAScore"].waitForExistence(timeout: 6),
            "the debounced commit must fire and reveal Game 2 once '1' (11-1) is no longer pending"
        )
    }

    /// Replaces a field's whole text deterministically: tap at the field's
    /// right edge (caret to the end), delete generously, then type. A
    /// double-tap "select the word" gesture proved unreliable here — on a
    /// two-digit value it left the caret between the digits, so typing
    /// inserted rather than replaced.
    private func replaceText(of field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        field.typeText(text)
    }

    /// Launches with a debug-only debounce override, switches to Best of 3
    /// and opens the Quick Log sheet.
    private func launchQuickLogBestOfThree(debounceMs: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-QuickLogDebounceMs", String(debounceMs)]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        let bestOfThree = app.buttons["Best of 3"]
        scrollUntilVisible(bestOfThree, in: app)
        bestOfThree.tap()

        let quickLogButton = app.buttons["Log Final Score Instead"]
        scrollUntilVisible(quickLogButton, in: app)
        quickLogButton.tap()
        return app
    }
}
