import XCTest

final class SavedPlayersUITests: XCTestCase {
    func testPlayingAMatchSavesPlayerNamesAsSuggestionsForTheNextMatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoMatchLimit", "2"]
        app.launch()

        dismissOnboardingIfPresented(app)
        app.tabBars.buttons["Play"].tap()

        // First match: type a fresh name, nothing to suggest yet.
        let flipCoinButton = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton, in: app)
        // NOTE: looked up by the stable identifier, not the "Player Name"
        // placeholder — playMode still defaults to .doubles at this point
        // (the Singles toggle below hasn't been tapped yet), so the
        // placeholder actually showing is "Player 1", not "Player Name".
        let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamAField, in: app)
        app.swipeUp() // ensure doubles/singles toggle and name fields are in view together
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }

        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText("Delon")

        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText("Mike")

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
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        // Second match: typing "Del" should surface a "Delon" suggestion chip.
        app.tabBars.buttons["Play"].tap()
        let teamATextField2 = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField2, in: app)
        teamATextField2.tap()
        teamATextField2.typeText("Del")

        let suggestionChip = app.buttons["PlayerSuggestion.Delon"]
        XCTAssertTrue(suggestionChip.waitForExistence(timeout: 2), "Delon should be suggested after playing a match with that name")
        suggestionChip.tap()
        XCTAssertEqual(teamATextField2.value as? String, "Delon")
    }

    func testLongPressingASuggestionChipOffersRemove() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)
        app.tabBars.buttons["Play"].tap()

        // Seed one saved player by playing a match named "Miek" (the typo
        // this gesture exists to let someone correct without visiting
        // Settings).
        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }
        teamATextField.tap()
        teamATextField.typeText("Miek")
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
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["Play"].tap()
        let teamATextField2 = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField2, in: app)
        teamATextField2.tap()
        teamATextField2.typeText("Mie")

        let chip = app.buttons["PlayerSuggestion.Miek"]
        XCTAssertTrue(chip.waitForExistence(timeout: 2))
        chip.press(forDuration: 1.0)
        let removeMenuItem = app.buttons["Remove"]
        XCTAssertTrue(removeMenuItem.waitForExistence(timeout: 2), "Long-pressing a suggestion chip should offer Remove")
        removeMenuItem.tap()

        XCTAssertFalse(app.buttons["PlayerSuggestion.Miek"].waitForExistence(timeout: 2), "Removed player should no longer appear as a suggestion")
    }

    func testMarkingAPlayerAsMeInManagePlayersEnforcesExactlyOne() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Create two players via a match, then go manage them.
        // NOTE: do NOT tap the "Singles" toggle here — this test needs two
        // players (Team A + Team B), which requires staying in the default
        // Doubles mode. Toggling to Singles removes the Team B field.
        app.tabBars.buttons["Play"].tap()
        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText("Alice")
        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        scrollUntilVisible(teamBTextField, in: app)
        teamBTextField.tap()
        teamBTextField.typeText("Bob")
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
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()

        let aliceMeButton = app.buttons["SetMe.Alice"]
        XCTAssertTrue(aliceMeButton.waitForExistence(timeout: 2))
        aliceMeButton.tap()
        XCTAssertTrue(app.staticTexts["Me.Alice"].waitForExistence(timeout: 2))

        let bobMeButton = app.buttons["SetMe.Bob"]
        bobMeButton.tap()
        XCTAssertTrue(app.staticTexts["Me.Bob"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Me.Alice"].exists, "Only one player should be marked Me at a time")
    }

    func testRenamingAPlayerInManagePlayersUpdatesTheDisplayedName() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }
        teamATextField.tap()
        teamATextField.typeText("Mike")
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
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()

        app.buttons["Rename.Mike"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        // The field is pre-filled with the current name ("Mike") — delete it
        // before typing the replacement, since typeText only appends.
        let existingValue = nameField.value as? String ?? ""
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count))
        nameField.typeText("Mike S.")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["PlayerRow.Mike S."].waitForExistence(timeout: 2), "Renamed player should appear under the new name")
        XCTAssertFalse(app.staticTexts["PlayerRow.Mike"].exists, "Old name should no longer be listed")
    }

    func testHomeShowsPersonalRecordOnceMeIsSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }
        teamATextField.tap()
        teamATextField.typeText("Delon")
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
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()
        app.buttons["SetMe.Delon"].tap()

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Your Record"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["1 - 0"].waitForExistence(timeout: 2))
    }
}
