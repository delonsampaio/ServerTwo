import XCTest
@testable import ServerTwo
import PickleballKit

@MainActor
final class ScoreCorrectionSheetTests: XCTestCase {
    private let elevenWinByTwo = GameConfiguration(winningScore: .eleven, winByTwo: true)

    private func canSave(
        _ configuration: GameConfiguration,
        from current: (Int, Int),
        to proposed: (Int, Int)
    ) -> Bool {
        ScoreCorrectionSheet.canSave(
            configuration: configuration,
            currentTeamA: current.0, currentTeamB: current.1,
            proposedTeamA: proposed.0, proposedTeamB: proposed.1
        )
    }

    func testSaveIsDisabledWhenNothingChanged() {
        XCTAssertFalse(canSave(elevenWinByTwo, from: (9, 9), to: (9, 9)))
    }

    func testSaveIsEnabledForAReachableChangedPair() {
        XCTAssertTrue(canSave(elevenWinByTwo, from: (9, 9), to: (12, 11)))
        XCTAssertTrue(canSave(elevenWinByTwo, from: (9, 10), to: (11, 10)))
    }

    func testSaveIsDisabledForAnUnreachablePair() {
        XCTAssertFalse(canSave(elevenWinByTwo, from: (9, 9), to: (12, 9)))
    }

    func testRecoveringFromAnAlreadyStuckGame() {
        // The CURRENT pair (12-9) is unreachable — a zombie left by older rules.
        // Save stays off while the user leaves it as-is, and turns on once
        // they dial in a reachable pair.
        XCTAssertFalse(canSave(elevenWinByTwo, from: (12, 9), to: (12, 9)))
        XCTAssertTrue(canSave(elevenWinByTwo, from: (12, 9), to: (12, 11)))
        XCTAssertTrue(canSave(elevenWinByTwo, from: (12, 9), to: (12, 10)))
    }

    func testWinByTwoOffRejectsAnOvertimePair() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: false)
        XCTAssertFalse(canSave(config, from: (9, 9), to: (12, 10)))
        XCTAssertTrue(canSave(config, from: (9, 9), to: (11, 10)))
    }

    func testFreezeAllowsAnyNonNegativePair() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: true), winningScore: .eleven, winByTwo: true)
        XCTAssertTrue(canSave(config, from: (9, 9), to: (20, 3)))
    }

    private func plan(
        from current: (Int, Int), to proposed: (Int, Int), swapChanged: Bool
    ) -> ScoreCorrectionSheet.SavePlan? {
        ScoreCorrectionSheet.savePlan(
            configuration: elevenWinByTwo,
            currentTeamA: current.0, currentTeamB: current.1,
            proposedTeamA: proposed.0, proposedTeamB: proposed.1,
            swapChanged: swapChanged
        )
    }

    func testASwapAloneEnablesSaveAndDoesNotCommitScores() {
        let swapOnly = plan(from: (9, 9), to: (9, 9), swapChanged: true)
        XCTAssertEqual(swapOnly, .init(commitsScores: false, commitsSwaps: true))
        XCTAssertTrue(ScoreCorrectionSheet.canSave(
            configuration: elevenWinByTwo, currentTeamA: 9, currentTeamB: 9,
            proposedTeamA: 9, proposedTeamB: 9, swapChanged: true
        ))
    }

    func testScoresAloneBehaveAsBefore() {
        XCTAssertEqual(plan(from: (9, 9), to: (12, 11), swapChanged: false), .init(commitsScores: true, commitsSwaps: false))
        XCTAssertNil(plan(from: (9, 9), to: (9, 9), swapChanged: false))
        XCTAssertNil(plan(from: (9, 9), to: (12, 9), swapChanged: false))
    }

    func testScoresAndASwapTogetherCommitBoth() {
        XCTAssertEqual(plan(from: (9, 9), to: (12, 11), swapChanged: true), .init(commitsScores: true, commitsSwaps: true))
    }

    func testAnUnreachableEditedPairKeepsSaveOffEvenWithASwap() {
        XCTAssertNil(plan(from: (9, 9), to: (12, 9), swapChanged: true))
    }

    func testASwapWorksInAGameWhoseCurrentPairIsAlreadyUnreachable() {
        XCTAssertEqual(plan(from: (12, 9), to: (12, 9), swapChanged: true), .init(commitsScores: false, commitsSwaps: true))
    }

    func testDesignHeightGrowsOnlyWhenASwapControlIsShown() {
        XCTAssertEqual(ScoreCorrectionSheet.designHeight(showsSwapControl: false), 360)
        XCTAssertEqual(ScoreCorrectionSheet.designHeight(showsSwapControl: true), 440)
    }

    func testHintMentionsTheTargetAndWinByTwoOnlyWhenEnabled() {
        let withWinByTwo = ScoreCorrectionSheet.hintText(configuration: elevenWinByTwo, teamA: 12, teamB: 9)
        XCTAssertTrue(withWinByTwo.contains("12"))
        XCTAssertTrue(withWinByTwo.contains("9"))
        XCTAssertTrue(withWinByTwo.contains("11"))
        XCTAssertTrue(withWinByTwo.contains("win by 2"))

        let withoutWinByTwo = ScoreCorrectionSheet.hintText(
            configuration: GameConfiguration(winningScore: .eleven, winByTwo: false), teamA: 12, teamB: 10
        )
        XCTAssertFalse(withoutWinByTwo.contains("win by 2"))
    }

    // MARK: footerStatus

    private func footer(
        _ configuration: GameConfiguration, _ a: Int, _ b: Int, changed: Bool
    ) -> ScoreCorrectionSheet.FooterStatus {
        ScoreCorrectionSheet.footerStatus(configuration: configuration, teamA: a, teamB: b, isChanged: changed)
    }

    func testFooterIsUnreachableForAnImpossiblePair() {
        guard case .unreachable(let text) = footer(elevenWinByTwo, 12, 9, changed: true) else {
            return XCTFail("expected .unreachable")
        }
        XCTAssertTrue(text.contains("12"))
    }

    func testFooterShowsTheRuleForAReachableInProgressPair() {
        XCTAssertEqual(footer(elevenWinByTwo, 12, 11, changed: true), .rule("Game to 11 • Win by 2"))
    }

    func testFooterWarnsThatSavingEndsTheGameForAChangedFinal() {
        XCTAssertEqual(footer(elevenWinByTwo, 11, 9, changed: true), .endsGame)
    }

    func testFooterShowsTheRuleForAnUnchangedFinal() {
        XCTAssertEqual(footer(elevenWinByTwo, 11, 9, changed: false), .rule("Game to 11 • Win by 2"))
    }

    func testFooterRuleOmitsWinByTwoWhenOff() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: false)
        guard case .rule(let text) = footer(config, 10, 9, changed: true) else {
            return XCTFail("expected .rule")
        }
        XCTAssertEqual(text, "Game to 11")
        XCTAssertFalse(text.contains("Win by 2"))
    }

    func testFooterEndsGameForAFreezeOvertimeFinal() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: true), winningScore: .eleven, winByTwo: true)
        XCTAssertEqual(footer(config, 20, 3, changed: true), .endsGame)
    }
}
