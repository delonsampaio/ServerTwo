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
        last: AnnouncementSnapshot.CompletedGame? = nil,
        moves: Int = 0
    ) -> AnnouncementSnapshot {
        AnnouncementSnapshot(
            gameIndex: index, teamAScore: a, teamBScore: b,
            servingTeam: serving, serverNumber: server, hasSideSwitched: switched,
            teamATimeoutsRemaining: ta, teamBTimeoutsRemaining: tb,
            teamAGamesWon: gamesA, teamBGamesWon: gamesB,
            isMatchOver: over, lastCompleted: last, moveCount: moves
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

    private func stakes(
        _ s: AnnouncementSnapshot, config: GameConfiguration? = nil, format: MatchFormat = .bestOfThree
    ) -> String? {
        AnnouncementPlanner.pointStakes(s, configuration: config ?? doublesSideOut, matchFormat: format)
    }

    // MARK: - The score call

    func testDoublesSideOutCallIsServingScoreReceivingScoreServerNumber() {
        XCTAssertEqual(plan(snap(a: 3, b: 2, server: .one), snap(a: 4, b: 2, server: .one)), ["4, 2, 1."])
    }

    func testTheServingTeamsScoreIsAlwaysSpokenFirst() {
        XCTAssertEqual(plan(snap(a: 2, b: 4, serving: .teamB, server: .two),
                            snap(a: 2, b: 5, serving: .teamB, server: .two)), ["5, 2, 2."])
    }

    func testAServerChangeWithoutAForwardMoveSpeaksOnlyTheCall() {
        XCTAssertEqual(plan(snap(a: 4, b: 2, server: .one), snap(a: 4, b: 2, server: .two)), ["4, 2, 2."])
    }

    func testASideOutWithoutAForwardMoveSpeaksOnlyTheNewServingTeamsCall() {
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

    // MARK: - Side out and second server (forward moves only)

    func testASideOutIsAnnouncedOnAForwardMove() {
        let old = snap(a: 4, b: 2, serving: .teamA, server: .two, moves: 5)
        let new = snap(a: 4, b: 2, serving: .teamB, server: .one, moves: 6)
        XCTAssertEqual(plan(old, new), ["Side out.", "2, 4, 1."])
    }

    func testASingleSideOutIsAnnouncedOnAForwardMove() {
        let singles = GameConfiguration(playMode: .singles, scoringFormat: .sideOut)
        let old = snap(a: 4, b: 2, serving: .teamA, server: .one, moves: 5)
        let new = snap(a: 4, b: 2, serving: .teamB, server: .one, moves: 6)
        XCTAssertEqual(plan(old, new, config: singles), ["Side out.", "2, 4."])
    }

    func testASideOutIsSilentOnUndo() {
        // Undo restores the previous serving team; the move count fell.
        let old = snap(a: 4, b: 2, serving: .teamB, server: .one, moves: 6)
        let new = snap(a: 4, b: 2, serving: .teamA, server: .two, moves: 5)
        XCTAssertEqual(plan(old, new), ["4, 2, 2."])
    }

    func testSecondServerIsAnnouncedWhenTheSameTeamKeepsTheServe() {
        let old = snap(a: 4, b: 2, serving: .teamA, server: .one, moves: 5)
        let new = snap(a: 4, b: 2, serving: .teamA, server: .two, moves: 6)
        XCTAssertEqual(plan(old, new), ["Second server.", "4, 2, 2."])
    }

    func testSecondServerIsSilentOnUndo() {
        let old = snap(a: 4, b: 2, serving: .teamA, server: .two, moves: 6)
        let new = snap(a: 4, b: 2, serving: .teamA, server: .one, moves: 5)
        XCTAssertEqual(plan(old, new), ["4, 2, 1."])
    }

    func testRallyScoringNeverSaysSideOut() {
        let rally = GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: false))
        let old = snap(a: 3, b: 2, serving: .teamA, server: .one, moves: 5)
        let new = snap(a: 3, b: 3, serving: .teamB, server: .one, moves: 6)
        XCTAssertEqual(plan(old, new, config: rally), ["3, 3."])
    }

    func testAScoringPointNeverSaysSideOutOrSecondServer() {
        let old = snap(a: 3, b: 2, serving: .teamA, server: .one, moves: 5)
        let new = snap(a: 4, b: 2, serving: .teamA, server: .one, moves: 6)
        XCTAssertEqual(plan(old, new), ["4, 2, 1."])
    }

    // MARK: - Side switch (last game of the format only), timeouts, silence

    func testCrossingTheThresholdSpeaksTheCallThenSwitchSides() {
        XCTAssertEqual(plan(snap(a: 5, b: 3, switched: false), snap(a: 6, b: 3, switched: true), format: .bestOfOne),
                       ["6, 3, 2.", "Switch sides."])
    }

    func testDroppingBackUnderTheThresholdSpeaksTheCallThenSwitchBack() {
        XCTAssertEqual(plan(snap(a: 6, b: 3, switched: true), snap(a: 5, b: 3, switched: false), format: .bestOfOne),
                       ["5, 3, 2.", "Switch back."])
    }

    func testNoSwitchLineWhenTheFlagDoesNotChange() {
        XCTAssertEqual(plan(snap(a: 6, b: 3, switched: true), snap(a: 7, b: 3, switched: true), format: .bestOfOne),
                       ["7, 3, 2."])
    }

    func testSwitchLinesOnlyApplyInTheLastGameOfTheFormat() {
        func crossing(index: Int, format: MatchFormat) -> [String] {
            plan(snap(index: index, a: 5, b: 3, switched: false), snap(index: index, a: 6, b: 3, switched: true), format: format)
        }
        XCTAssertEqual(crossing(index: 0, format: .bestOfOne), ["6, 3, 2.", "Switch sides."])
        XCTAssertEqual(crossing(index: 0, format: .bestOfThree), ["6, 3, 2."])
        XCTAssertEqual(crossing(index: 1, format: .bestOfThree), ["6, 3, 2."])
        XCTAssertEqual(crossing(index: 2, format: .bestOfThree), ["6, 3, 2.", "Switch sides."])
        XCTAssertEqual(crossing(index: 3, format: .bestOfFive), ["6, 3, 2."])
        XCTAssertEqual(crossing(index: 4, format: .bestOfFive), ["6, 3, 2.", "Switch sides."])
    }

    func testMatchFormatKnowsItsLastGame() {
        XCTAssertTrue(MatchFormat.bestOfOne.isLastGame(index: 0))
        XCTAssertFalse(MatchFormat.bestOfOne.isLastGame(index: 1))
        XCTAssertFalse(MatchFormat.bestOfThree.isLastGame(index: 0))
        XCTAssertFalse(MatchFormat.bestOfThree.isLastGame(index: 1))
        XCTAssertTrue(MatchFormat.bestOfThree.isLastGame(index: 2))
        XCTAssertFalse(MatchFormat.bestOfFive.isLastGame(index: 3))
        XCTAssertTrue(MatchFormat.bestOfFive.isLastGame(index: 4))
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

    // MARK: - Game point and match point

    func testGamePointIsSpokenAfterTheCall() {
        let old = snap(a: 9, b: 8, serving: .teamA, server: .one, moves: 3)
        let new = snap(a: 10, b: 8, serving: .teamA, server: .one, moves: 4)
        XCTAssertEqual(plan(old, new), ["10, 8, 1.", "Game point."])
    }

    func testMatchPointReplacesGamePointWhenTheGameWouldClinchTheMatch() {
        let old = snap(a: 9, b: 8, serving: .teamA, server: .one, gamesA: 1, moves: 3)
        let new = snap(a: 10, b: 8, serving: .teamA, server: .one, gamesA: 1, moves: 4)
        XCTAssertEqual(plan(old, new), ["10, 8, 1.", "Match point."])
        // Best of one: every game point is match point.
        XCTAssertEqual(plan(snap(a: 9, b: 8, server: .one, moves: 3), snap(a: 10, b: 8, server: .one, moves: 4), format: .bestOfOne),
                       ["10, 8, 1.", "Match point."])
    }

    func testSideOutIntoGamePointSpeaksBothCalls() {
        // Team B (8) was serving, Team A has 10; B loses the rally.
        let old = snap(a: 10, b: 8, serving: .teamB, server: .two, moves: 5)
        let new = snap(a: 10, b: 8, serving: .teamA, server: .one, moves: 6)
        XCTAssertEqual(plan(old, new), ["Side out.", "10, 8, 1.", "Game point."])
    }

    func testSecondServerOnGamePointSpeaksBothCalls() {
        let old = snap(a: 10, b: 8, serving: .teamA, server: .one, moves: 5)
        let new = snap(a: 10, b: 8, serving: .teamA, server: .two, moves: 6)
        XCTAssertEqual(plan(old, new), ["Second server.", "10, 8, 2.", "Game point."])
    }

    func testASideOutToATeamThatIsBehindIsNotGamePoint() {
        // Team B (10) loses its second serve; Team A (8) now serves. A cannot win on the next point.
        let old = snap(a: 8, b: 10, serving: .teamB, server: .two, moves: 5)
        let new = snap(a: 8, b: 10, serving: .teamA, server: .one, moves: 6)
        XCTAssertEqual(plan(old, new), ["Side out.", "8, 10, 1."])
    }

    func testUndoingATimeoutOnAGamePointBoardIsSilent() {
        let old = snap(a: 10, b: 8, server: .one, ta: 1, moves: 5)
        let new = snap(a: 10, b: 8, server: .one, ta: 2, moves: 4)
        XCTAssertEqual(plan(old, new), [])
    }

    func testATimeoutOnAGamePointBoardSpeaksOnlyTheTimeout() {
        let old = snap(a: 10, b: 8, server: .one, ta: 2, moves: 4)
        let new = snap(a: 10, b: 8, server: .one, ta: 1, moves: 5)
        XCTAssertEqual(plan(old, new), ["Timeout, Delon."])
    }

    func testACorrectionLandingOnGamePointInTheLastGameSpeaksCallSwitchAndStakes() {
        let old = snap(a: 0, b: 0, moves: 0)
        let new = snap(a: 10, b: 8, server: .two, switched: true, moves: 1)
        XCTAssertEqual(plan(old, new, format: .bestOfOne), ["10, 8, 2.", "Switch sides.", "Match point."])
    }

    func testStakesNeedTheTeamToBeStrictlyAheadAfterTheNextPoint() {
        XCTAssertEqual(stakes(snap(a: 10, b: 8)), "Game point.")
        XCTAssertNil(stakes(snap(a: 10, b: 10)))                       // 11-10 is not a win by two
        XCTAssertEqual(stakes(snap(a: 11, b: 10)), "Game point.")      // 12-10
        XCTAssertEqual(stakes(snap(a: 12, b: 11)), "Game point.")      // 13-11
        XCTAssertNil(stakes(snap(a: 8, b: 10)))                        // 9 is behind 10 (the strictly-ahead guard itself is exercised by the rally-freeze 13-10 test below)
        XCTAssertNil(stakes(snap(a: 10, b: 8, serving: .teamB)))       // serving team has 8
        XCTAssertEqual(stakes(snap(a: 8, b: 10, serving: .teamB)), "Game point.")
    }

    func testStakesFollowTheGameTarget() {
        let to15 = GameConfiguration(playMode: .doubles, scoringFormat: .sideOut, winningScore: .fifteen)
        XCTAssertEqual(stakes(snap(a: 14, b: 9), config: to15), "Game point.")
        XCTAssertNil(stakes(snap(a: 13, b: 9), config: to15))
    }

    func testStakesRallyFreezeWithTheReceiverAheadHasNoGamePoint() {
        // Rally freeze: the receiving team can pass the target with a lead without ending the game.
        // 13-10 with the 10-point team serving: 10 + 1 = 11 is still behind 13.
        let freeze = GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: true))
        XCTAssertNil(stakes(snap(a: 13, b: 10, serving: .teamB), config: freeze))
        // Only the serving team can end the game under the freeze rule.
        XCTAssertEqual(stakes(snap(a: 10, b: 8, serving: .teamA), config: freeze), "Game point.")
        XCTAssertNil(stakes(snap(a: 10, b: 8, serving: .teamB), config: freeze))
    }

    func testStakesRallyWithoutFreezeLetsEitherTeamWin() {
        let rally = GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: false), winByTwo: false)
        XCTAssertEqual(stakes(snap(a: 10, b: 10, serving: .teamA), config: rally), "Game point.")
        // Team A is one game from the match; it can win on this rally, so it is match point
        // even though Team B (0 games) also could win the game.
        XCTAssertEqual(stakes(snap(a: 10, b: 10, serving: .teamB, gamesA: 1), config: rally), "Match point.")
        XCTAssertNil(stakes(snap(a: 5, b: 4), config: rally))
    }

    // MARK: - Games and matches

    func testAGameCompletedWhileTheFlagWasTrueSpeaksNoSwitchLine() {
        let old = snap(index: 0, a: 10, b: 3, switched: true)
        let new = snap(index: 1, a: 0, b: 0, switched: false, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 3.", "Switch sides.", "Next game, 0, 0, 2."])
    }

    func testAGameCompletedNamesTheWinnerSwitchesSidesAndCallsTheNextGame() {
        let old = snap(index: 0, a: 10, b: 3)
        let new = snap(index: 1, a: 0, b: 0, serving: .teamA, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 3.", "Switch sides.", "Next game, 0, 0, 2."])
    }

    func testTeamBWinningAGameSpeaksTheWinnersScoreFirst() {
        let old = snap(index: 1, a: 7, b: 10, gamesA: 1)
        let new = snap(index: 2, a: 0, b: 0, serving: .teamB, gamesA: 1, gamesB: 1,
                       last: .init(teamAScore: 7, teamBScore: 11, winner: .teamB))
        XCTAssertEqual(plan(old, new), ["Game 2 to Fred, 11 to 7.", "Switch sides.", "Next game, 0, 0, 2."])
    }

    func testAGameWithNoEngineWinnerFallsBackToTheHigherScore() {
        let old = snap(index: 0, a: 10, b: 9)
        let new = snap(index: 1, gamesA: 1, last: .init(teamAScore: 11, teamBScore: 9, winner: nil))
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 9.", "Switch sides.", "Next game, 0, 0, 2."])
    }

    func testTheNextGameCallFollowsTheScoringFormat() {
        let singles = GameConfiguration(playMode: .singles, scoringFormat: .sideOut)
        let old = snap(index: 0, a: 10, b: 3)
        let new = snap(index: 1, serving: .teamA, server: .one, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        XCTAssertEqual(plan(old, new, config: singles),
                       ["Game 1 to Delon, 11 to 3.", "Switch sides.", "Next game, 0, 0."])
    }

    func testABestOfOneMatchOverIsGameAndMatch() {
        let old = snap(index: 0, a: 10, b: 5)
        let new = snap(index: 1, a: 11, b: 5, gamesA: 1, over: true,
                       last: .init(teamAScore: 11, teamBScore: 5, winner: .teamA))
        XCTAssertEqual(plan(old, new, format: .bestOfOne), ["Game and match, Delon, 11 to 5."])
    }

    func testABestOfThreeClincherSpeaksTheFinalGameThenGameAndMatch() {
        let old = snap(index: 1, a: 10, b: 9, gamesA: 1)
        let new = snap(index: 2, a: 11, b: 9, gamesA: 2, over: true,
                       last: .init(teamAScore: 11, teamBScore: 9, winner: .teamA))
        XCTAssertEqual(plan(old, new), ["Game 2 to Delon, 11 to 9.", "Game and match, Delon, 2 games to 0."])
    }

    func testTeamBClinchingASeriesSpeaksTheWinnersGamesFirst() {
        let old = snap(index: 2, a: 9, b: 10, gamesA: 1, gamesB: 1)
        let new = snap(index: 3, a: 9, b: 11, gamesA: 1, gamesB: 2, over: true,
                       last: .init(teamAScore: 9, teamBScore: 11, winner: .teamB))
        XCTAssertEqual(plan(old, new), ["Game 3 to Fred, 11 to 9.", "Game and match, Fred, 2 games to 1."])
    }

    func testGameCompletedWinsOverASideSwitchInTheSameChange() {
        // One correction from 0-0 to 11-9 ends a best-of-1 match. The finished
        // game's flag is true (the correction crossed the threshold), so a
        // planner that checked the side switch before the game index would
        // add "Switch sides." Only the match line may be spoken.
        let old = snap(index: 0, a: 0, b: 0, switched: false)
        let new = snap(index: 1, a: 11, b: 9, switched: true, gamesA: 1, over: true,
                       last: .init(teamAScore: 11, teamBScore: 9, winner: .teamA))
        XCTAssertEqual(plan(old, new, format: .bestOfOne), ["Game and match, Delon, 11 to 9."])
    }

    func testUndoingBackIntoThePreviousGameSpeaksTheRestoredCallAndStakesButNoSwitchLine() {
        // The restored game's flag is true; the game index fell, so no
        // "Switch sides." / "Switch back." is spoken. Stakes still describe the board.
        let old = snap(index: 1, a: 0, b: 0, switched: false, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        let new = snap(index: 0, a: 10, b: 3, server: .one, switched: true)
        XCTAssertEqual(plan(old, new), ["10, 3, 1.", "Game point."])
    }

    func testUndoingBackIntoAGameWithNoStakesSpeaksOnlyTheCall() {
        let old = snap(index: 1, a: 0, b: 0, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        let new = snap(index: 0, a: 6, b: 3, server: .one, switched: true)
        XCTAssertEqual(plan(old, new), ["6, 3, 1."])   // 6 + 1 = 7 is not a completed score
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
        XCTAssertEqual(start.moveCount, 0)

        match.recordPoint(for: .teamA)
        XCTAssertEqual(AnnouncementSnapshot(match: match).moveCount, 1, "each forward move adds one")
        match.undo()
        XCTAssertEqual(AnnouncementSnapshot(match: match).moveCount, 0, "undo takes one away")

        for _ in 0..<11 { match.recordPoint(for: .teamA) }   // serving team scores 11-0
        let after = AnnouncementSnapshot(match: match)
        XCTAssertEqual(after.gameIndex, 1)
        XCTAssertEqual(after.teamAGamesWon, 1)
        XCTAssertEqual(after.lastCompleted, .init(teamAScore: 11, teamBScore: 0, winner: .teamA))
        XCTAssertEqual(after.teamAScore, 0)   // the new game
        XCTAssertEqual(after.moveCount, 0)    // a fresh game has no moves
        XCTAssertFalse(after.isMatchOver)
        XCTAssertEqual(
            AnnouncementPlanner.plan(from: start, to: after, configuration: doublesSideOut,
                                     matchFormat: .bestOfThree, teamAName: "Delon", teamBName: "Fred"),
            ["Game 1 to Delon, 11 to 0.", "Switch sides.", "Next game, 0, 0, 2."]
        )
    }
}
