import XCTest
@testable import PickleballKit

final class PickleballGameDemoCapTests: XCTestCase {
    func testGameIsNotPaywalledWhenProUnlocked() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: 5)
        for _ in 1...10 { game.recordPoint(for: .teamA) }
        XCTAssertFalse(game.isPaywalled)
        XCTAssertEqual(game.state.teamAScore, 10)
    }

    func testGameBlocksScoringPastTheCapWhenNotUnlocked() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isPaywalled)
        XCTAssertEqual(game.state.teamAScore, 5)

        game.recordPoint(for: .teamA) // blocked
        XCTAssertEqual(game.state.teamAScore, 5)
    }

    func testUnlockProRemovesThePaywallAndAllowsPlayToContinue() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isPaywalled)

        game.unlockPro()
        XCTAssertFalse(game.isPaywalled)
        game.recordPoint(for: .teamA)
        XCTAssertEqual(game.state.teamAScore, 6)
    }

    func testUndoingBelowTheCapUnblocksScoringWithoutPurchase() {
        // Review Focus: isPaywalled must never go stale after an undo.
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isPaywalled)

        game.undo() // back to 4
        XCTAssertFalse(game.isPaywalled)
        XCTAssertEqual(game.state.teamAScore, 4)

        game.recordPoint(for: .teamA) // allowed again, back to 5
        XCTAssertEqual(game.state.teamAScore, 5)
        XCTAssertTrue(game.isPaywalled)
    }
}
