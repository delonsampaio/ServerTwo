import XCTest

/// Accessibility audit harness. Runs XCUITest's
/// `app.performAccessibilityAudit()` on each main screen and records every
/// issue it reports.
///
/// Every issue is recorded and printed (grep the xcodebuild log for
/// `A11Y-AUDIT|`). With `strict` on, an issue that does not match an entry of
/// `AccessibilityAuditExceptions.all` fails the test; with it off the class is
/// report-only.
///
/// Log line format (one line per issue):
/// `A11Y-AUDIT|<screen>|<auditType>|<element identifier or label>|<compactDescription>|<detailedDescription>`
/// and one `A11Y-AUDIT-SUMMARY|<screen>|<count>` line per audit call.
///
/// If an audit call itself throws (as opposed to reporting issues), the test
/// fails; that is deliberately not swallowed.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    /// While `false` this is report-only (every issue is recorded and
    /// ignored). While `true` any issue that does not match an entry of
    /// `AccessibilityAuditExceptions.all` (in `AccessibilityAuditExceptions.swift`,
    /// each entry with a reason) fails the test.
    private let strict = true

    /// Every issue recorded during this test run, as the printed log lines.
    private var recordedIssues: [String] = []

    // MARK: - Harness

    /// Runs the audit on the current screen. `anchor` is an element that must
    /// be present and hittable before auditing, then a short fixed settle
    /// lets transitions and animations finish. The settle lives only here so
    /// every audit gets the same treatment.
    private func audit(_ app: XCUIApplication, screen: String, anchor: XCUIElement) throws {
        let ready = expectation(
            for: NSPredicate(format: "exists == true AND isHittable == true"),
            evaluatedWith: anchor
        )
        wait(for: [ready], timeout: 5)
        Thread.sleep(forTimeInterval: 0.5)

        var countForScreen = 0
        // How often each exception has been used during this audit call; an
        // entry only absorbs up to its `maxOccurrences` issues.
        var usedCounts: [Int: Int] = [:]
        try app.performAccessibilityAudit { [self] issue in
            let type = Self.name(for: issue.auditType)
            let elementID = Self.elementDescription(issue.element)
            let description = Self.sanitize(issue.compactDescription)
            let detailed = Self.sanitize(issue.detailedDescription)
            let line = "A11Y-AUDIT|\(screen)|\(type)|\(elementID)|\(description)|\(detailed)"
            recordedIssues.append(line)
            countForScreen += 1
            print(line)

            if !strict { return true }
            let matchingID = Self.dateNormalized(elementID)
            let matches = AccessibilityAuditExceptions.all.enumerated().filter { _, entry in
                entry.screen == screen && entry.auditType == type && entry.elements.contains(matchingID)
                    && description.contains(entry.descriptionContains)
            }
            // The first matching entry that still has room absorbs the issue.
            guard let match = matches.first(where: { index, entry in
                usedCounts[index, default: 0] < entry.maxOccurrences
            }) else { return false }
            usedCounts[match.offset, default: 0] += 1
            return true
        }
        let summary = "A11Y-AUDIT-SUMMARY|\(screen)|\(countForScreen)"
        print(summary)

        let attachment = XCTAttachment(
            string: ([summary] + recordedIssues.filter { $0.hasPrefix("A11Y-AUDIT|\(screen)|") })
                .joined(separator: "\n")
        )
        attachment.name = "Accessibility audit: \(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func elementDescription(_ element: XCUIElement?) -> String {
        guard let element else { return "(no element)" }
        let identifier = element.identifier
        if !identifier.isEmpty { return sanitize(identifier) }
        let label = element.label
        if !label.isEmpty { return sanitize("label:" + label) }
        return "(unnamed \(element.elementType.rawValue))"
    }

    /// Elements named by a date (the History and Match Detail date labels)
    /// change every day; exceptions refer to them as `label:<date>`.
    private static func dateNormalized(_ element: String) -> String {
        element.replacingOccurrences(
            of: #"label:[A-Z][a-z]+ \d{1,2}, \d{4}"#, with: "label:<date>", options: .regularExpression
        )
    }

    /// Keeps each record on a single line and free of the field separator.
    private static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "/")
    }

    private static func name(for type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"),
            (.elementDetection, "elementDetection"),
            (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"),
            (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"),
            (.trait, "trait"),
        ]
        let matched = names.filter { type.contains($0.0) }.map(\.1)
        return matched.isEmpty ? "raw(\(type.rawValue))" : matched.joined(separator: "+")
    }

    // MARK: - Navigation helpers

    private func launchApp(
        extraArguments: [String] = [],
        dismissOnboarding: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"] + extraArguments
        app.launch()
        if dismissOnboarding {
            dismissOnboardingIfPresented(app)
        }
        return app
    }

    /// Play tab -> Start Match -> the coin-flip ("First Serve") screen.
    private func openCoinFlip(_ app: XCUIApplication, teamA: String? = nil, teamB: String? = nil) {
        app.tabBars.buttons["Play"].tap()
        // Names (doubles mode, one field per team) create saved players when
        // the match finishes; see SavedPlayersUITests.
        if let teamA {
            let field = app.textFields.matching(identifier: "Team A Player Name").firstMatch
            scrollUntilVisible(field, in: app)
            field.tap()
            field.typeText(teamA)
        }
        if let teamB {
            let field = app.textFields.matching(identifier: "Team B Player Name").firstMatch
            scrollUntilVisible(field, in: app)
            field.tap()
            field.typeText(teamB)
        }
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()
        XCTAssertTrue(app.buttons["Flip Coin"].waitForExistence(timeout: 3))
    }

    /// Coin-flip screen -> Flip Coin -> Begin Match -> live scoring screen.
    private func beginMatchFromCoinFlip(_ app: XCUIApplication) {
        app.buttons["Flip Coin"].tap()
        let beginMatchButton = app.buttons["Begin Match"]
        XCTAssertTrue(beginMatchButton.waitForExistence(timeout: 3))
        beginMatchButton.tap()
        XCTAssertTrue(app.buttons["scoreZone.teamA"].waitForExistence(timeout: 3))
    }

    /// Plays one full one-game match to 11 and confirms finishing it, as
    /// `GoldenPathUITests` does. Leaves the app on the Play tab's setup screen.
    private func playAndFinishOneMatch(_ app: XCUIApplication, teamA: String? = nil, teamB: String? = nil) {
        openCoinFlip(app, teamA: teamA, teamB: teamB)
        beginMatchFromCoinFlip(app)
        let teamAZone = app.buttons["scoreZone.teamA"]
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        XCTAssertTrue(finishButton.waitForExistence(timeout: 2), "Match should finish well within 20 Team A points")
        finishButton.tap()
        // Wrapper + inner Button both expose this identifier; see GoldenPathUITests.
        app.buttons["Confirm Finish"].firstMatch.tap()
        // Wait for the match to actually end before navigating anywhere else.
        let finished = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: finishButton)
        wait(for: [finished], timeout: 5)
    }

    /// Audits the live scoring screen, then the Cancel Match prompt, then
    /// taps "Keep Playing". `suffix` distinguishes screen names between runs.
    private func auditScoringAndCancelPrompt(_ app: XCUIApplication, suffix: String = "") throws {
        try audit(app, screen: "Scoring" + suffix, anchor: app.buttons["scoreZone.teamA"])

        app.buttons["Cancel Match"].tap()
        let keepPlaying = app.buttons["Prompt.KeepPlaying"]
        XCTAssertTrue(keepPlaying.waitForExistence(timeout: 3))
        try audit(app, screen: "CancelMatchPrompt" + suffix, anchor: keepPlaying)
        keepPlaying.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: keepPlaying)
        waitForExpectations(timeout: 3)
    }

    // MARK: - Tests

    func testHome() throws {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 3))
        try audit(app, screen: "Home", anchor: app.buttons["New Match"])
    }

    func testMatchSetup() throws {
        let app = launchApp()
        app.tabBars.buttons["Play"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
        try audit(app, screen: "MatchSetup", anchor: app.navigationBars.firstMatch)
    }

    func testCoinFlip() throws {
        let app = launchApp()
        openCoinFlip(app)
        try audit(app, screen: "CoinFlip", anchor: app.buttons["Flip Coin"])
    }

    func testScoring() throws {
        let app = launchApp()
        openCoinFlip(app)
        beginMatchFromCoinFlip(app)
        try auditScoringAndCancelPrompt(app)
    }

    func testHistoryAndMatchDetail() throws {
        let app = launchApp()
        playAndFinishOneMatch(app)

        app.tabBars.buttons["History"].tap()
        let row = app.staticTexts["Team A vs Team B"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        try audit(app, screen: "History", anchor: row)

        row.tap()
        // The detail screen replaces the list; give it a moment to settle.
        XCTAssertTrue(
            app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 3),
            "Match detail should push a navigation bar with a back button"
        )
        try audit(app, screen: "MatchDetail", anchor: app.navigationBars.buttons.firstMatch)

        // Home with a finished match in history: Last Match card, quick-start
        // row, matches-played card and the Home unlock banner. (No saved
        // "Me" here, so the Your Record card is covered in testPlayersAndSettings.)
        app.tabBars.buttons["Home"].tap()
        try audit(app, screen: "HomeWithMatch", anchor: app.buttons["New Match"])
    }

    func testPlayersAndSettings() throws {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()
        let managePlayers = app.buttons["Manage Players"]
        XCTAssertTrue(managePlayers.waitForExistence(timeout: 3))
        try audit(app, screen: "Settings", anchor: managePlayers)

        managePlayers.tap()
        XCTAssertTrue(app.navigationBars["Manage Players"].waitForExistence(timeout: 3))
        try audit(app, screen: "ManagePlayers", anchor: app.navigationBars["Manage Players"])

        // Pop back to Settings' root so the tab shows it again later.
        app.navigationBars.buttons.firstMatch.tap()

        // Create two saved players (a named match saves both), set one as Me,
        // then audit the populated list and the Home record card.
        playAndFinishOneMatch(app, teamA: "Alice", teamB: "Bob")
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()
        let setAliceAsMe = app.buttons["SetMe.Alice"]
        XCTAssertTrue(setAliceAsMe.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["SetMe.Bob"].exists, "Both players should be saved")
        setAliceAsMe.tap()
        let aliceRow = app.staticTexts["Me.Alice"]
        XCTAssertTrue(aliceRow.waitForExistence(timeout: 3))
        try audit(app, screen: "ManagePlayersWithRows", anchor: aliceRow)

        app.tabBars.buttons["Home"].tap()
        let record = app.staticTexts["YourRecordValue"]
        XCTAssertTrue(record.waitForExistence(timeout: 3), "Home should show the record card once Me is set")
        try audit(app, screen: "HomeWithMatchAndMe", anchor: record)
    }

    func testHowToPlay() throws {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()
        let link = app.buttons["How to Play Pickleball"]
        scrollUntilVisible(link, in: app)
        link.tap()
        XCTAssertTrue(app.navigationBars["How to Play"].waitForExistence(timeout: 3))
        try audit(app, screen: "HowToPlay", anchor: app.navigationBars["How to Play"])
    }

    func testOnboarding() throws {
        // Audit BEFORE dismissing: -UITest-ResetState re-presents onboarding.
        let app = launchApp(dismissOnboarding: false)
        let presented = app.buttons["Done"].waitForExistence(timeout: 5)
            || app.buttons["Skip"].waitForExistence(timeout: 1)
        XCTAssertTrue(presented, "Onboarding should be presented after -UITest-ResetState")
        let onboardingAnchor = app.buttons["Done"].exists ? app.buttons["Done"] : app.buttons["Skip"]
        try audit(app, screen: "Onboarding", anchor: onboardingAnchor)
    }

    func testPaywall() throws {
        // The Home unlock banner only appears once a match exists, so reuse
        // PaywallTriggerUITests' flow: with a demo limit of 1, finish one
        // match, then Start Match presents the paywall.
        let app = launchApp(extraArguments: ["-UITest-DemoMatchLimit", "1"])
        playAndFinishOneMatch(app)
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()
        let unlockButton = app.buttons["Unlock Pro — $1.99"]
        XCTAssertTrue(
            unlockButton.waitForExistence(timeout: 3),
            "Starting a second match should present the paywall"
        )
        try audit(app, screen: "Paywall", anchor: unlockButton)
    }

    func testScoringAtAccessibilitySize() throws {
        // 1. Default-size launch: capture the coin-flip subtitle height.
        let defaultApp = launchApp()
        openCoinFlip(defaultApp)
        let defaultSubtitle = defaultApp.staticTexts["FirstServeResult"]
        XCTAssertTrue(defaultSubtitle.waitForExistence(timeout: 3))
        let defaultHeight = defaultSubtitle.frame.height
        defaultApp.terminate()

        // 2. Accessibility-size launch (still -UITest-ResetState + onboarding
        //    dismissal): the same element must be taller, otherwise the launch
        //    argument silently fell back to the default size.
        let app = launchApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXL",
        ])
        openCoinFlip(app)
        let largeSubtitle = app.staticTexts["FirstServeResult"]
        XCTAssertTrue(largeSubtitle.waitForExistence(timeout: 3))
        let largeHeight = largeSubtitle.frame.height
        XCTAssertGreaterThanOrEqual(
            largeHeight,
            defaultHeight * 1.5,
            "Accessibility XXL should enlarge the subtitle at least 1.5x (default \(defaultHeight), large \(largeHeight)); the content-size launch argument did not apply"
        )
        print("A11Y-AUDIT-SIZECHECK|FirstServeResult height default=\(defaultHeight) axxl=\(largeHeight)")

        beginMatchFromCoinFlip(app)
        try auditScoringAndCancelPrompt(app, suffix: "@AXXL")
    }

    /// The two sheets that sit on top of the scoring screen and carry its
    /// primary actions: Game Over (best of 3) and Finish Match (best of 1),
    /// at accessibility size 4. Their primary buttons must be hittable (not
    /// pushed off the sheet), and each sheet is audited as its own screen.
    func testSheetsAtAccessibilitySize() throws {
        let axArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXL",
        ]

        // Game Over: finish game 1 of a best of 3 (the match goes on).
        let gameOverApp = launchApp(extraArguments: axArguments)
        gameOverApp.tabBars.buttons["Play"].tap()
        let bestOfThree = gameOverApp.buttons["Best of 3"]
        scrollUntilVisible(bestOfThree, in: gameOverApp)
        bestOfThree.tap()
        let startMatchButton = gameOverApp.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: gameOverApp)
        startMatchButton.tap()
        XCTAssertTrue(gameOverApp.buttons["Flip Coin"].waitForExistence(timeout: 3))
        beginMatchFromCoinFlip(gameOverApp)
        let gameOverZone = gameOverApp.buttons["scoreZone.teamA"]
        let startNextGame = gameOverApp.buttons["Prompt.Dismiss"]
        for _ in 0..<20 {
            if startNextGame.exists { break }
            gameOverZone.tap()
        }
        XCTAssertTrue(startNextGame.waitForExistence(timeout: 5), "Game 1 should end within 20 Team A points")
        XCTAssertTrue(gameOverApp.otherElements["Prompt.GameOver"].exists)
        let gameOverReady = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: startNextGame)
        wait(for: [gameOverReady], timeout: 5)
        XCTAssertTrue(startNextGame.isHittable, "Start Game 2 must be reachable at accessibility size 4")
        try audit(gameOverApp, screen: "GameOverSheet@AXXL", anchor: startNextGame)
        gameOverApp.terminate()

        // Finish Match: finish a best of 1 and open the confirmation sheet.
        let finishApp = launchApp(extraArguments: axArguments)
        openCoinFlip(finishApp)
        beginMatchFromCoinFlip(finishApp)
        let finishZone = finishApp.buttons["scoreZone.teamA"]
        let finishButton = finishApp.buttons["Finish Match"]
        // The last game of the format shows the Switch Sides sheet at 6
        // points; at accessibility size it covers the score zones, so
        // dismiss it before the next tap.
        let switchSidesDismiss = finishApp.buttons["Prompt.Dismiss"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            if switchSidesDismiss.exists {
                switchSidesDismiss.tap()
                let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: switchSidesDismiss)
                wait(for: [gone], timeout: 3)
            }
            finishZone.tap()
        }
        XCTAssertTrue(finishButton.waitForExistence(timeout: 2), "Match should finish well within 20 Team A points")
        finishButton.tap()
        // Wrapper + inner Button both expose this identifier; see GoldenPathUITests.
        let confirmFinish = finishApp.buttons["Confirm Finish"].firstMatch
        XCTAssertTrue(confirmFinish.waitForExistence(timeout: 3))
        let finishReady = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: confirmFinish)
        wait(for: [finishReady], timeout: 5)
        XCTAssertTrue(confirmFinish.isHittable, "Confirm Finish must be reachable at accessibility size 4")
        try audit(finishApp, screen: "FinishMatchSheet@AXXL", anchor: confirmFinish)
    }
}
