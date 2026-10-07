import XCTest
@testable import PickleballKit

final class PickleballGameRallyTests: XCTestCase {
    func testRallyPointAlwaysScoresAndPassesServeToWinner() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false))
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)

        game.recordPoint(for: .teamB) // teamB wins the rally despite receiving
        XCTAssertEqual(game.state.teamBScore, 1)
        XCTAssertEqual(game.state.servingTeam, .teamB)

        game.recordPoint(for: .teamB) // teamB wins again, now serving
        XCTAssertEqual(game.state.teamBScore, 2)
        XCTAssertEqual(game.state.servingTeam, .teamB)
    }

    func testWinByTwoRequiresTwoPointMarginUnderRallyScoring() {
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: false),
            winningScore: .eleven,
            winByTwo: true
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...10 { game.recordPoint(for: .teamA) }
        game.recordPoint(for: .teamB) // 10-1, teamA still well ahead
        for _ in 1...9 { game.recordPoint(for: .teamB) } // teamB climbs to 10
        XCTAssertEqual(game.state.teamAScore, 10)
        XCTAssertEqual(game.state.teamBScore, 10)
        XCTAssertFalse(game.isGameOver) // 10-10, margin 0

        game.recordPoint(for: .teamA) // 11-10, margin 1
        XCTAssertFalse(game.isGameOver)

        game.recordPoint(for: .teamA) // 12-10, margin 2
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }

    func testFreezePreventsWinningOnARallyThatJustTookOverServe() {
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: true),
            winningScore: .eleven,
            winByTwo: true
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...9 { game.recordPoint(for: .teamA) } // 9-0, teamA serving
        game.recordPoint(for: .teamB) // 9-1, teamB now serving (took over)
        for _ in 1...8 { game.recordPoint(for: .teamB) } // 9-9, teamB serving throughout

        // teamB now wins what would be an 11-9 qualifying margin while
        // ALREADY serving (has held serve since 9-1) -> this IS a
        // legitimate on-serve win, not blocked by freeze.
        game.recordPoint(for: .teamB) // 9-10
        game.recordPoint(for: .teamB) // 9-11, margin 2, teamB was already serving
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamB)
    }

    func testFreezeBlocksWinOnTheExactRallyServeChangesHands() {
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: true),
            winningScore: .eleven,
            winByTwo: true
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...10 { game.recordPoint(for: .teamA) } // 10-0, teamA serving throughout
        for _ in 1...9 { game.recordPoint(for: .teamB) }  // teamB takes over serve and climbs to 9: 10-9, teamB serving
        XCTAssertEqual(game.state.teamAScore, 10)
        XCTAssertEqual(game.state.teamBScore, 9)
        XCTAssertEqual(game.state.servingTeam, .teamB)

        // teamA takes over serve on this exact rally: 11-9, margin 2 —
        // qualifies on score alone, but must be blocked because serve just
        // changed hands on this very rally.
        game.recordPoint(for: .teamA)
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.gameWinner)
        XCTAssertEqual(game.state.servingTeam, .teamA) // serve still passes to the rally winner as normal

        // teamA wins again, now already serving: 12-9, margin 3 -> legitimate win.
        game.recordPoint(for: .teamA)
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }

    // MARK: - Fix 1: a tie is never a win, regardless of winByTwo

    func testTiedScoreAtOrAboveTargetIsNeverAWinWhenWinByTwoIsFalse() {
        // Critical bug: gameWinner used to compute `leader: Team = a > b ?
        // .teamA : .teamB`, which falls through to .teamB on a tie. With
        // winByTwo false there was nothing blocking a tied score at/above
        // the target from being returned as a teamB win.
        //
        // Natural sequential recordPoint() play can never actually reach a
        // tie at the target once winByTwo is off, because the moment either
        // team first reaches the target while strictly ahead the game
        // freezes (recordPoint no-ops once isGameOver is true). So we use
        // correctScore (which has no isGameOver guard) to construct the tie
        // directly and exercise gameWinner's own tie-handling.
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: false),
            winningScore: .eleven,
            winByTwo: false
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.correctScore(team: .teamA, to: 11)
        game.correctScore(team: .teamB, to: 11)

        XCTAssertEqual(game.state.teamAScore, 11)
        XCTAssertEqual(game.state.teamBScore, 11)
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.gameWinner)
    }

    func testReachingTargetWithAnyLeadWinsImmediatelyWhenWinByTwoIsFalse() {
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: false),
            winningScore: .eleven,
            winByTwo: false
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...10 {
            game.recordPoint(for: .teamA)
            game.recordPoint(for: .teamB)
        }
        XCTAssertEqual(game.state.teamAScore, 10)
        XCTAssertEqual(game.state.teamBScore, 10)
        XCTAssertFalse(game.isGameOver)

        // teamA takes an 11-10 lead -- only a 1-point margin, which is
        // sufficient to win immediately since winByTwo is off.
        game.recordPoint(for: .teamA)
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }
}
