import XCTest
@testable import ServerTwo
import PickleballKit

@MainActor
final class AnnouncementPlannerTests: XCTestCase {
    private let doublesSideOut = GameConfiguration(playMode: .doubles, scoringFormat: .sideOut)

    private func snap(
        index: Int = 0, a: Int = 0, b: Int = 0,
        serving: Team = .teamA, server: ServerNumber = .two,
        switched: Bool = false, ta: Int = 2, tb: Int = 2,
        gamesA: Int = 0, gamesB: Int = 0, over: Bool = false,
        last: AnnouncementSnapshot.CompletedGame? = nil
    ) -> AnnouncementSnapshot {
        AnnouncementSnapshot(
            gameIndex: index, teamAScore: a, teamBScore: b,
            servingTeam: serving, serverNumber: server, hasSideSwitched: switched,
            teamATimeoutsRemaining: ta, teamBTimeoutsRemaining: tb,
            teamAGamesWon: gamesA, teamBGamesWon: gamesB,
            isMatchOver: over, lastCompleted: last
        )
    }

    private func plan(
        _ old: AnnouncementSnapshot, _ new: AnnouncementSnapshot,
        config: GameConfiguration? = nil, format: MatchFormat = .bestOfThree
    ) -> [String] {
        AnnouncementPlanner.plan(
            from: old, to: new, configuration: config ?? doublesSideOut,
            matchFormat: format, teamAName: "Delon", teamBName: "Fred"
        )
    }

    // MARK: - The score call

    func testDoublesSideOutCallIsServingScoreReceivingScoreServerNumber() {
        XCTAssertEqual(plan(snap(a: 3, b: 2, server: .one), snap(a: 4, b: 2, server: .one)), ["4, 2, 1."])
    }

    func testTheServingTeamsScoreIsAlwaysSpokenFirst() {
        XCTAssertEqual(plan(snap(a: 2, b: 4, serving: .teamB, server: .two),
                            snap(a: 2, b: 5, serving: .teamB, server: .two)), ["5, 2, 2."])
    }

    func testAServerChangeWithinTheSameTeamSpeaksTheNewServerNumber() {
        XCTAssertEqual(plan(snap(a: 4, b: 2, server: .one), snap(a: 4, b: 2, server: .two)), ["4, 2, 2."])
    }

    func testASideOutSpeaksTheNewServingTeamsScoreFirst() {
        XCTAssertEqual(plan(snap(a: 4, b: 2, serving: .teamA, server: .two),
                            snap(a: 4, b: 2, serving: .teamB, server: .one)), ["2, 4, 1."])
    }

    func testSinglesCallHasTwoNumbers() {
        let singles = GameConfiguration(playMode: .singles, scoringFormat: .sideOut)
        XCTAssertEqual(plan(snap(a: 3, b: 2, server: .one), snap(a: 4, b: 2, server: .one), config: singles), ["4, 2."])
    }

    func testRallyScoringCallHasTwoNumbersEvenInDoubles() {
        let rally = GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: false))
        XCTAssertEqual(plan(snap(a: 3, b: 2, server: .one), snap(a: 4, b: 2, server: .one), config: rally), ["4, 2."])
    }

    func testAFreshDoublesGameIsCalledZeroZeroTwo() {
        XCTAssertEqual(AnnouncementPlanner.scoreCall(snap(), configuration: doublesSideOut), "0, 0, 2")
    }

    // MARK: - Side switch, timeouts, silence

    func testCrossingTheThresholdSpeaksTheCallThenSwitchSides() {
        XCTAssertEqual(plan(snap(a: 5, b: 3, switched: false), snap(a: 6, b: 3, switched: true)),
                       ["6, 3, 2.", "Switch sides."])
    }

    func testDroppingBackUnderTheThresholdSpeaksTheCallThenSwitchBack() {
        XCTAssertEqual(plan(snap(a: 6, b: 3, switched: true), snap(a: 5, b: 3, switched: false)),
                       ["5, 3, 2.", "Switch back."])
    }

    func testNoSwitchLineWhenTheFlagDoesNotChange() {
        XCTAssertEqual(plan(snap(a: 6, b: 3, switched: true), snap(a: 7, b: 3, switched: true)), ["7, 3, 2."])
    }

    func testATimeoutNamesTheTeamThatTookIt() {
        XCTAssertEqual(plan(snap(ta: 2), snap(ta: 1)), ["Timeout, Delon."])
        XCTAssertEqual(plan(snap(tb: 2), snap(tb: 1)), ["Timeout, Fred."])
    }

    func testUndoingATimeoutIsSilent() {
        XCTAssertEqual(plan(snap(ta: 1), snap(ta: 2)), [])
    }

    func testNoChangeIsSilent() {
        XCTAssertEqual(plan(snap(a: 4, b: 2), snap(a: 4, b: 2)), [])
    }

    // MARK: - Games and matches

    func testAGameCompletedNamesTheWinnerAndCallsTheNextGame() {
        let old = snap(index: 0, a: 10, b: 3)
        let new = snap(index: 1, a: 0, b: 0, serving: .teamA, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 3.", "Next game, 0, 0, 2."])
    }

    func testTeamBWinningAGameSpeaksTheWinnersScoreFirst() {
        let old = snap(index: 1, a: 7, b: 10, gamesA: 1)
        let new = snap(index: 2, a: 0, b: 0, serving: .teamB, gamesA: 1, gamesB: 1,
                       last: .init(teamAScore: 7, teamBScore: 11, winner: .teamB))
        XCTAssertEqual(plan(old, new), ["Game 2 to Fred, 11 to 7.", "Next game, 0, 0, 2."])
    }

    func testAGameWithNoEngineWinnerFallsBackToTheHigherScore() {
        let old = snap(index: 0, a: 10, b: 9)
        let new = snap(index: 1, gamesA: 1, last: .init(teamAScore: 11, teamBScore: 9, winner: nil))
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 9.", "Next game, 0, 0, 2."])
    }

    func testTheNextGameCallFollowsTheScoringFormat() {
        let singles = GameConfiguration(playMode: .singles, scoringFormat: .sideOut)
        let old = snap(index: 0, a: 10, b: 3)
        let new = snap(index: 1, serving: .teamA, server: .one, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        XCTAssertEqual(plan(old, new, config: singles), ["Game 1 to Delon, 11 to 3.", "Next game, 0, 0."])
    }

    func testABestOfOneMatchOverSpeaksOnlyTheWinnerAndScore() {
        let old = snap(index: 0, a: 10, b: 5)
        let new = snap(index: 1, a: 11, b: 5, gamesA: 1, over: true,
                       last: .init(teamAScore: 11, teamBScore: 5, winner: .teamA))
        XCTAssertEqual(plan(old, new, format: .bestOfOne), ["Delon wins, 11 to 5."])
    }

    func testABestOfThreeClincherSpeaksTheFinalGameThenTheMatch() {
        let old = snap(index: 1, a: 10, b: 9, gamesA: 1)
        let new = snap(index: 2, a: 11, b: 9, gamesA: 2, over: true,
                       last: .init(teamAScore: 11, teamBScore: 9, winner: .teamA))
        XCTAssertEqual(plan(old, new), ["Game 2 to Delon, 11 to 9.", "Delon wins the match, 2 to 0."])
    }

    func testTeamBClinchingASeriesSpeaksTheWinnersGamesFirst() {
        let old = snap(index: 2, a: 9, b: 10, gamesA: 1, gamesB: 1)
        let new = snap(index: 3, a: 9, b: 11, gamesA: 1, gamesB: 2, over: true,
                       last: .init(teamAScore: 9, teamBScore: 11, winner: .teamB))
        XCTAssertEqual(plan(old, new), ["Game 3 to Fred, 11 to 9.", "Fred wins the match, 2 to 1."])
    }

    func testGameCompletedWinsOverASideSwitchInTheSameChange() {
        // One correction from 0-0 to 11-9 ends a best-of-1 match. The finished
        // game's flag is true (the correction crossed the threshold), so a
        // planner that checked the side switch before the game index would
        // add "Switch sides." Only the match line may be spoken.
        let old = snap(index: 0, a: 0, b: 0, switched: false)
        let new = snap(index: 1, a: 11, b: 9, switched: true, gamesA: 1, over: true,
                       last: .init(teamAScore: 11, teamBScore: 9, winner: .teamA))
        XCTAssertEqual(plan(old, new, format: .bestOfOne), ["Delon wins, 11 to 9."])
    }

    func testUndoingBackIntoThePreviousGameSpeaksOnlyTheRestoredCall() {
        // The restored game's flag is true; the game index fell, so no
        // "Switch sides." / "Switch back." is spoken.
        let old = snap(index: 1, a: 0, b: 0, switched: false, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        let new = snap(index: 0, a: 10, b: 3, server: .one, switched: true)
        XCTAssertEqual(plan(old, new), ["10, 3, 1."])
    }

    // MARK: - Snapshot from a real match

    func testSnapshotReflectsALiveMatchAcrossAGameBoundary() {
        let match = PickleballMatch(
            configuration: doublesSideOut, matchFormat: .bestOfThree,
            firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil
        )
        let start = AnnouncementSnapshot(match: match)
        XCTAssertEqual(start.gameIndex, 0)
        XCTAssertNil(start.lastCompleted)
        XCTAssertEqual(start.serverNumber, .two)

        for _ in 0..<11 { match.recordPoint(for: .teamA) }   // serving team scores 11-0
        let after = AnnouncementSnapshot(match: match)
        XCTAssertEqual(after.gameIndex, 1)
        XCTAssertEqual(after.teamAGamesWon, 1)
        XCTAssertEqual(after.lastCompleted, .init(teamAScore: 11, teamBScore: 0, winner: .teamA))
        XCTAssertEqual(after.teamAScore, 0)   // the new game
        XCTAssertFalse(after.isMatchOver)
        XCTAssertEqual(
            AnnouncementPlanner.plan(from: start, to: after, configuration: doublesSideOut,
                                     matchFormat: .bestOfThree, teamAName: "Delon", teamBName: "Fred"),
            ["Game 1 to Delon, 11 to 0.", "Next game, 0, 0, 2."]
        )
    }
}
