import XCTest
@testable import ServerTwo
import PickleballKit

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
}
