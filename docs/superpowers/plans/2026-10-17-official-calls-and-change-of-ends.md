# Official Calls and Change of Ends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Voice Announcer sound more like an official referee ("Side out.", "Second server.", "Game point."/"Match point.", "Change ends.", "Game and match, ...") and make the mid-game Switch Sides prompt and call follow the official change-of-ends rule (only in the last game of the match format).

**Architecture:** Wording lives in the existing pure `AnnouncementPlanner` (plus one new `moveCount` field on `AnnouncementSnapshot` to tell forward moves from undo). A one-line pure helper `MatchFormat.isLastGame(index:)` is shared by the planner and by `ScoringView`'s side-switch prompt gate. The Game Over sheet gets one extra line. No engine (PickleballKit) changes.

**Tech Stack:** Swift 5 mode app target with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI, XCTest/XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-17-official-calls-and-change-of-ends-design.md` (approved by the user; rule text verified against the official 2026 USA Pickleball Official Rulebook). Builds on `docs/superpowers/specs/2026-10-16-voice-announcer-design.md`.

## Global Constraints

- Cite ONLY these rule numbers anywhere (code comments, docs): Rule 6.B (calling the score), 14.A (rally scoring), 17.D.4 / 17.D.5 ("second server", "side out" referee calls), 21.B (mid-game end change in a single or tie-breaker game), 21.F.2 (end change and initial service change between games). No other rule numbers.
- All new/changed app code stays in the app target; do NOT change PickleballKit. Do not hand-edit `project.pbxproj` (file-system-synchronized groups).
- Planner lines are full sentences ending in a period; `VoiceAnnouncer` joins them with a space into one utterance (unchanged).
- Composition order of one same-game change, at most these slots in this order: (1) prefix `"Side out."` or `"Second server."`, (2) score call, (3) `"Switch sides."`/`"Switch back."` (last game of the format only), (4) `"Match point."` or `"Game point."` (only when the call changed).
- Game point uses `canWinOnNextPoint`: the team's score + 1 must be STRICTLY greater than the opponent's AND `configuration.isCompletedGameScore` true for the resulting pair (that function is symmetric; the strict-greater guard is required).
- Eligible teams for game point: serving team only for side-out and rally freeze; both teams for rally without freeze. `"Match point."` replaces `"Game point."` when any team that can win on the next point has `gamesWon + 1 >= matchFormat.gamesToWin`.
- "Side out." / "Second server." only when `new.moveCount > old.moveCount`, scores unchanged, side-out scoring (`"Second server."` also doubles only).
- Test conventions: app tests ONLY on the iOS 27 simulator `3C7D4B7A-F035-4AD7-89FF-B08256AF2516`, serially: `xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:<Target/Class> -resultBundlePath /tmp/<name>.xcresult`, verified ONLY with `xcrun xcresulttool get test-results summary --path /tmp/<name>.xcresult` (print `result, passedTests, failedTests, totalTestCount`). Never `name=iPhone 17 Pro`. If xcodebuild hangs 10+ minutes after a failure, `pkill -f xcodebuild` and rerun once; "Timed out while loading Accessibility" means rerun. No `timeout` command on macOS. SourceKit shows false "No such module" errors; trust `xcodebuild`.
- Test classes that touch app types are `@MainActor`. Test output must be pristine: after the full-suite run, grep the build log for warnings from the changed files.
- Stage specific files only; NEVER stage `ServerTwo.xcodeproj/xcuserdata/**/xcschememanagement.plist`. Do not push. Commit messages end with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Symmetric score check:** a trailing serving team must not hear "Game point." when the other team already holds a winning-looking score (rally freeze 13-10, 10-point team serving). (Task 1: `testStakesRallyFreezeWithTheReceiverAheadHasNoGamePoint`.)
2. **Undo must not say "Side out." / "Second server.":** forward-only via `moveCount`. (Task 1: `testASideOutIsSilentOnUndo`, `testSecondServerIsSilentOnUndo`.)
3. **Undoing a timeout on a game-point board stays silent.** (Task 1: `testUndoingATimeoutOnAGamePointBoardIsSilent`.)
4. **Mid-game Switch Sides only in the last game of the format** for the planner AND the prompt sheet. (Task 1: `testSwitchLinesOnlyApplyInTheLastGameOfTheFormat`; Task 2: the extended `ScoringPromptsUITests` first test asserts NO sheet at 6-0 in game 1 of a best of 3, while `testSideSwitchPromptsAgainAfterUndoAndRecrossing` (best of 1) still shows it.)
5. **The Game Over sheet keeps its existing "Next game starts at 0-0." text element** (an existing UI test asserts it) and gains a separate "Teams change ends." element. (Task 2.)

---

### Task 1: Planner wording, `moveCount`, and `MatchFormat.isLastGame`

**Files:**
- Create: `ServerTwo/Scoring/MatchFormat+LastGame.swift`
- Modify: `ServerTwo/Voice/AnnouncementSnapshot.swift`
- Modify: `ServerTwo/Voice/AnnouncementPlanner.swift` (full replacement)
- Modify: `ServerTwoTests/AnnouncementPlannerTests.swift` (full replacement)

**Interfaces:**
- Consumes: `PickleballGame.history` (public, `[GameState]`), `GameConfiguration.isCompletedGameScore(teamA:teamB:)`, `GameConfiguration.scoringFormat` (`Equatable`: `.sideOut`, `.rally(freeze:)`), `MatchFormat.gamesToWin`, `MatchFormat.rawValue` (1/3/5).
- Produces: `MatchFormat.isLastGame(index: Int) -> Bool`; `AnnouncementSnapshot.moveCount: Int` (memberwise init gains `moveCount:` as the LAST parameter); `AnnouncementPlanner.plan(...)` (same signature) with the new wording; `AnnouncementPlanner.pointStakes(_ snapshot: AnnouncementSnapshot, configuration: GameConfiguration, matchFormat: MatchFormat) -> String?` (internal, for tests).

- [ ] **Step 1: Write the failing tests (full file replacement)**

Replace the ENTIRE contents of `ServerTwoTests/AnnouncementPlannerTests.swift` with:

```swift
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
        XCTAssertNil(stakes(snap(a: 8, b: 10)))                        // 9 is not ahead of 10
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
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 3.", "Change ends.", "Next game, 0, 0, 2."])
    }

    func testAGameCompletedNamesTheWinnerChangesEndsAndCallsTheNextGame() {
        let old = snap(index: 0, a: 10, b: 3)
        let new = snap(index: 1, a: 0, b: 0, serving: .teamA, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 3.", "Change ends.", "Next game, 0, 0, 2."])
    }

    func testTeamBWinningAGameSpeaksTheWinnersScoreFirst() {
        let old = snap(index: 1, a: 7, b: 10, gamesA: 1)
        let new = snap(index: 2, a: 0, b: 0, serving: .teamB, gamesA: 1, gamesB: 1,
                       last: .init(teamAScore: 7, teamBScore: 11, winner: .teamB))
        XCTAssertEqual(plan(old, new), ["Game 2 to Fred, 11 to 7.", "Change ends.", "Next game, 0, 0, 2."])
    }

    func testAGameWithNoEngineWinnerFallsBackToTheHigherScore() {
        let old = snap(index: 0, a: 10, b: 9)
        let new = snap(index: 1, gamesA: 1, last: .init(teamAScore: 11, teamBScore: 9, winner: nil))
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 9.", "Change ends.", "Next game, 0, 0, 2."])
    }

    func testTheNextGameCallFollowsTheScoringFormat() {
        let singles = GameConfiguration(playMode: .singles, scoringFormat: .sideOut)
        let old = snap(index: 0, a: 10, b: 3)
        let new = snap(index: 1, serving: .teamA, server: .one, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        XCTAssertEqual(plan(old, new, config: singles),
                       ["Game 1 to Delon, 11 to 3.", "Change ends.", "Next game, 0, 0."])
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
            ["Game 1 to Delon, 11 to 0.", "Change ends.", "Next game, 0, 0, 2."]
        )
    }
}
```

- [ ] **Step 2: Run to verify it fails to compile**

Run: `rm -rf /tmp/planner2.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:ServerTwoTests/AnnouncementPlannerTests -resultBundlePath /tmp/planner2.xcresult > /tmp/planner2.log 2>&1; grep -E "error:" /tmp/planner2.log | head -5`
Expected: errors such as "extra argument 'moveCount' in call", "value of type 'MatchFormat' has no member 'isLastGame'", "type 'AnnouncementPlanner' has no member 'pointStakes'".

- [ ] **Step 3: Implement the helper, snapshot field and planner**

Create `ServerTwo/Scoring/MatchFormat+LastGame.swift`:

```swift
import PickleballKit

extension MatchFormat {
    /// The mid-game end change (Rule 21.B) applies only to a single game or the
    /// tie-breaker (deciding) game of a multi-game match: the last game the
    /// format can reach (game 1 of a best of 1, game 3 of a best of 3, game 5
    /// of a best of 5). Between games teams always change ends (Rule 21.F.2).
    func isLastGame(index: Int) -> Bool {
        index == rawValue - 1
    }
}
```

In `ServerTwo/Voice/AnnouncementSnapshot.swift`: add the stored property after `lastCompleted` and pass it in `init(match:)`:

```swift
    /// Final score and winner of the most recently completed game, if any.
    var lastCompleted: CompletedGame?
    /// `currentGame.history.count`: rises with every forward move (point,
    /// timeout, correction) and falls on undo, so the planner can tell
    /// "Side out." (a forward move) from an undo that restored the serve.
    var moveCount: Int
```

and in the `self.init(...)` call of `init(match:)`, after the `lastCompleted:` argument (add a comma after the closing `}` of its `.map`):

```swift
            lastCompleted: match.completedGames.last.map {
                CompletedGame(
                    teamAScore: $0.state.teamAScore,
                    teamBScore: $0.state.teamBScore,
                    winner: $0.gameWinner
                )
            },
            moveCount: match.currentGame.history.count
```

Replace the ENTIRE contents of `ServerTwo/Voice/AnnouncementPlanner.swift` with:

```swift
import PickleballKit

/// Turns "what changed on the scoring screen" into the sentences to speak.
/// Pure and stateless. Every returned line is a full sentence ending in a
/// period; `VoiceAnnouncer` joins them with a space into one utterance.
///
/// One same-game change composes at most four slots, in this order:
/// 1. prefix: "Side out." or "Second server." (forward moves only),
/// 2. the score call,
/// 3. "Switch sides." / "Switch back." (last game of the format only),
/// 4. "Match point." / "Game point." (only when the call was spoken).
enum AnnouncementPlanner {
    static func plan(
        from old: AnnouncementSnapshot,
        to new: AnnouncementSnapshot,
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        teamAName: String,
        teamBName: String
    ) -> [String] {
        func name(_ team: Team) -> String { team == .teamA ? teamAName : teamBName }

        // The completed-game count is checked FIRST so one multi-field change
        // (e.g. a correction that crosses the side-switch threshold and ends
        // the game) never produces conflicting lines.
        if new.gameIndex > old.gameIndex {
            guard let done = new.lastCompleted else {
                return [scoreCall(new, configuration: configuration) + "."]
            }
            let winner: Team = done.winner ?? (done.teamAScore >= done.teamBScore ? .teamA : .teamB)
            let winnerScore = winner == .teamA ? done.teamAScore : done.teamBScore
            let loserScore = winner == .teamA ? done.teamBScore : done.teamAScore
            if new.isMatchOver {
                if matchFormat == .bestOfOne {
                    return ["Game and match, \(name(winner)), \(winnerScore) to \(loserScore)."]
                }
                let matchWinner: Team = new.teamAGamesWon > new.teamBGamesWon ? .teamA : .teamB
                let winnerGames = matchWinner == .teamA ? new.teamAGamesWon : new.teamBGamesWon
                let loserGames = matchWinner == .teamA ? new.teamBGamesWon : new.teamAGamesWon
                return [
                    "Game \(new.gameIndex) to \(name(winner)), \(winnerScore) to \(loserScore).",
                    "Game and match, \(name(matchWinner)), \(winnerGames) games to \(loserGames).",
                ]
            }
            // Teams change ends after every completed game (Rule 21.F.2).
            return [
                "Game \(new.gameIndex) to \(name(winner)), \(winnerScore) to \(loserScore).",
                "Change ends.",
                "Next game, \(scoreCall(new, configuration: configuration)).",
            ]
        }

        // An undo that reopened the previous game: just the restored call.
        if new.gameIndex < old.gameIndex {
            return [scoreCall(new, configuration: configuration) + "."]
        }

        var lines: [String] = []
        if new.teamATimeoutsRemaining < old.teamATimeoutsRemaining {
            lines.append("Timeout, \(teamAName).")
        }
        if new.teamBTimeoutsRemaining < old.teamBTimeoutsRemaining {
            lines.append("Timeout, \(teamBName).")
        }
        if !lines.isEmpty { return lines }

        let scoresUnchanged = old.teamAScore == new.teamAScore && old.teamBScore == new.teamBScore
        let callChanged = !scoresUnchanged
            || old.servingTeam != new.servingTeam
            || old.serverNumber != new.serverNumber

        // 1. Referee calls (Rule 17.D.4, 17.D.5): only when nobody scored, on a
        // FORWARD move, in side-out scoring. An undo that restores the serve
        // must not announce a side out that did not just happen.
        if callChanged, scoresUnchanged, new.moveCount > old.moveCount,
           configuration.scoringFormat == .sideOut {
            if old.servingTeam != new.servingTeam {
                lines.append("Side out.")
            } else if configuration.playMode == .doubles, old.serverNumber == .one, new.serverNumber == .two {
                lines.append("Second server.")
            }
        }

        // 2. The score call.
        if callChanged {
            lines.append(scoreCall(new, configuration: configuration) + ".")
        }

        // 3. Mid-game change of ends: last game of the format only (Rule 21.B).
        if matchFormat.isLastGame(index: new.gameIndex) {
            if !old.hasSideSwitched && new.hasSideSwitched {
                lines.append("Switch sides.")
            } else if old.hasSideSwitched && !new.hasSideSwitched {
                lines.append("Switch back.")
            }
        }

        // 4. Stakes, only alongside a spoken call (never on a timeout undo).
        if callChanged, let stakes = pointStakes(new, configuration: configuration, matchFormat: matchFormat) {
            lines.append(stakes)
        }
        return lines
    }

    /// Serving team's score, receiving team's score, then (doubles side-out
    /// only) the server number. Rally scoring and singles omit it
    /// (Rules 6.B, 14.A).
    static func scoreCall(_ snapshot: AnnouncementSnapshot, configuration: GameConfiguration) -> String {
        let servingScore = snapshot.servingTeam == .teamA ? snapshot.teamAScore : snapshot.teamBScore
        let receivingScore = snapshot.servingTeam == .teamA ? snapshot.teamBScore : snapshot.teamAScore
        var parts = ["\(servingScore)", "\(receivingScore)"]
        if configuration.playMode == .doubles, configuration.scoringFormat == .sideOut {
            parts.append("\(snapshot.serverNumber.rawValue)")
        }
        return parts.joined(separator: ", ")
    }

    /// "Match point." / "Game point." when a team that can end the game on the
    /// next point exists (a courtesy call, not a rulebook call). Side-out and
    /// rally freeze: only the serving team can; rally without freeze: either.
    static func pointStakes(
        _ snapshot: AnnouncementSnapshot,
        configuration: GameConfiguration,
        matchFormat: MatchFormat
    ) -> String? {
        let eligible: [Team]
        switch configuration.scoringFormat {
        case .sideOut:
            eligible = [snapshot.servingTeam]
        case .rally(let freeze):
            eligible = freeze ? [snapshot.servingTeam] : [.teamA, .teamB]
        }
        let winners = eligible.filter { canWinOnNextPoint($0, in: snapshot, configuration: configuration) }
        guard !winners.isEmpty else { return nil }
        let clinches = winners.contains { team in
            let games = team == .teamA ? snapshot.teamAGamesWon : snapshot.teamBGamesWon
            return games + 1 >= matchFormat.gamesToWin
        }
        return clinches ? "Match point." : "Game point."
    }

    /// `isCompletedGameScore` is symmetric (it looks at max/min), so the team
    /// must also be strictly ahead after the point; otherwise a trailing
    /// serving team would be reported at game point whenever the other team
    /// already holds a winning-looking score (reachable in rally freeze).
    private static func canWinOnNextPoint(
        _ team: Team,
        in snapshot: AnnouncementSnapshot,
        configuration: GameConfiguration
    ) -> Bool {
        let ownNext = (team == .teamA ? snapshot.teamAScore : snapshot.teamBScore) + 1
        let opponent = team == .teamA ? snapshot.teamBScore : snapshot.teamAScore
        guard ownNext > opponent else { return false }
        return team == .teamA
            ? configuration.isCompletedGameScore(teamA: ownNext, teamB: opponent)
            : configuration.isCompletedGameScore(teamA: opponent, teamB: ownNext)
    }
}
```

- [ ] **Step 4: Run the planner tests**

Run the Step 2 command, then `xcrun xcresulttool get test-results summary --path /tmp/planner2.xcresult | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:d.get(k) for k in ('result','passedTests','failedTests','totalTestCount')})"`
Expected: `Passed`, 45 tests, 0 failed. If a stakes test fails, hand-trace the expected value against `isCompletedGameScore` (src: `PickleballKit/Sources/PickleballKit/GameConfiguration.swift`) before changing anything; fix the TEST only where its hand trace was wrong and report it.

- [ ] **Step 5: Also run the other Voice tests, then commit**

Run the same command with `-only-testing:ServerTwoTests/VoiceAnnouncerTests -only-testing:ServerTwoTests/SystemSpeechOutputTests -only-testing:ServerTwoTests/MyAppSpeechOutputTests` (they must still pass untouched), then:

```bash
git add ServerTwo/Scoring/MatchFormat+LastGame.swift ServerTwo/Voice/AnnouncementSnapshot.swift ServerTwo/Voice/AnnouncementPlanner.swift ServerTwoTests/AnnouncementPlannerTests.swift
git commit -m "$(cat <<'EOF'
Announcer: official calls (side out, second server, game/match point, change ends)

Forward-only referee calls via a move count, stakes that need the team to be
strictly ahead, official game-and-match endings, and the mid-game switch
line only in the last game of the match format.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Gate the Switch Sides prompt, add "Teams change ends.", verify

**Files:**
- Modify: `ServerTwo/Scoring/ScoringView.swift` (`syncSideSwitchPrompt`, currently ~lines 222-240)
- Modify: `ServerTwo/Scoring/ScoringPromptSheet.swift` (`gameOver(...)`, currently ~lines 246-275; add a static constant next to the other static copy helpers)
- Modify: `ServerTwoTests/ScoringPromptSheetTests.swift` (one test)
- Modify: `ServerTwoUITests/ScoringPromptsUITests.swift` (`testGameOverAfterCorrectionThenCancelMatchPrompt`)
- Modify: `docs/superpowers/specs/2026-10-17-official-calls-and-change-of-ends-design.md` (append "As built")

**Interfaces:**
- Consumes: Task 1's `MatchFormat.isLastGame(index:)`.
- Produces: the user-visible behavior.

- [ ] **Step 1: Write the failing unit test**

Add to `ServerTwoTests/ScoringPromptSheetTests.swift` (inside the class, next to `testGamesTallyLine`):

```swift
    func testGameOverSheetSaysTeamsChangeEnds() {
        XCTAssertEqual(ScoringPromptSheet.changeEndsLine, "Teams change ends.")
    }
```

Run `-only-testing:ServerTwoTests/ScoringPromptSheetTests` (same command shape, result bundle `/tmp/sheet2.xcresult`); expected: compile error "type 'ScoringPromptSheet' has no member 'changeEndsLine'".

- [ ] **Step 2: Implement the sheet line**

In `ServerTwo/Scoring/ScoringPromptSheet.swift`, next to the other `static` copy helpers (for example beside `gamesTallyLine`), add:

```swift
    /// Teams change ends after every completed game (Rule 21.F.2). A separate
    /// line, so the existing "Next game starts at 0-0." text element is
    /// unchanged.
    static let changeEndsLine = "Teams change ends."
```

In the `gameOver(...)` view, replace:

```swift
            VStack(spacing: 4) {
                Text(Self.gamesTallyLine(teamAGames: teamAGames, teamBGames: teamBGames))
                    .font(.subheadline.weight(.semibold))
                Text("Next game starts at 0-0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
```

with:

```swift
            VStack(spacing: 4) {
                Text(Self.gamesTallyLine(teamAGames: teamAGames, teamBGames: teamBGames))
                    .font(.subheadline.weight(.semibold))
                Text(Self.changeEndsLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Next game starts at 0-0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
```

The sheet's fixed detent for Game Over is chosen in this file (search for `detentHeight`): the extra line adds roughly 20 pt. Capture a temporary screenshot of the Game Over sheet (the existing UI test reaches it; use `xcrun simctl io 3C7D4B7A-F035-4AD7-89FF-B08256AF2516 screenshot /tmp/gameover.png` while it is up, or a temporary `XCTAttachment`) and LOOK at it: nothing clipped, the dismiss button fully visible. If it clips, raise the Game Over detent by the smallest amount that fixes it. Remove any temporary screenshot code before committing.

- [ ] **Step 3: Gate the prompt in `ScoringView`**

In `ServerTwo/Scoring/ScoringView.swift`, in `syncSideSwitchPrompt()`, immediately after `let gameIndex = match.completedGames.count`, add:

```swift
        // The mid-game end change applies only in the last game of the match
        // format (Rule 21.B). Between games teams always change ends (Rule
        // 21.F.2), which the Game Over sheet and the spoken game line say.
        guard match.matchFormat.isLastGame(index: gameIndex) else { return }
```

so the function reads:

```swift
    private func syncSideSwitchPrompt() {
        guard let match = activeMatchController.match, !match.isMatchOver else { return }
        let gameIndex = match.completedGames.count
        guard match.matchFormat.isLastGame(index: gameIndex) else { return }
        guard let direction = sideSwitchTracker.next(
            ...
```

Do not change anything else in the prompt queue, tracker, or stale logic.

- [ ] **Step 4: Extend the UI test**

In `ServerTwoUITests/ScoringPromptsUITests.swift`, in `testGameOverAfterCorrectionThenCancelMatchPrompt`, replace this block:

```swift
        // Correct to 11-0: a finished game, so Save ends game 1.
        let save = app.buttons["ScoreCorrection.Save"]
        teamAZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        let teamAIncrement = app.buttons["ScoreCorrection.TeamAIncrement"]
        for _ in 0..<11 { teamAIncrement.tap() }
        save.tap()

        let dismissButton = app.buttons["Prompt.Dismiss"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5), "Game Over prompt never appeared after the correction sheet closed")
```

with:

```swift
        let save = app.buttons["ScoreCorrection.Save"]
        let teamAIncrement = app.buttons["ScoreCorrection.TeamAIncrement"]
        let dismissButton = app.buttons["Prompt.Dismiss"]

        // The mid-game change of ends applies only in the last game of the
        // format, so reaching 6 in game 1 of a best of 3 must NOT show the
        // Switch Sides sheet.
        teamAZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        for _ in 0..<6 { teamAIncrement.tap() }
        save.tap()
        XCTAssertFalse(dismissButton.waitForExistence(timeout: 2), "no Switch Sides sheet in game 1 of a best of 3")

        // Correct from 6-0 to 11-0: a finished game, so Save ends game 1.
        teamAZone.press(forDuration: 1.0)
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        for _ in 0..<5 { teamAIncrement.tap() }
        save.tap()

        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5), "Game Over prompt never appeared after the correction sheet closed")
```

and, directly after the existing line `XCTAssertTrue(app.staticTexts["Next game starts at 0-0."].exists)`, add:

```swift
        XCTAssertTrue(app.staticTexts["Teams change ends."].exists)
```

Leave `testSideSwitchPromptsAgainAfterUndoAndRecrossing` unchanged (it uses the default best of 1, where the prompt still applies) and confirm by reading that it never selects a different match format. `ScoreCorrectionUITests` also uses the default best of 1 and stays unchanged.

- [ ] **Step 5: Run the focused tests**

Run (result bundle `/tmp/gating.xcresult`): `-only-testing:ServerTwoTests/ScoringPromptSheetTests -only-testing:ServerTwoUITests/ScoringPromptsUITests -only-testing:ServerTwoUITests/ScoreCorrectionUITests`. Verify with xcresulttool. Expected: all passed (ScoringPromptSheetTests count +1).

- [ ] **Step 6: Run the full suite once and check for warnings**

Run the full suite once: `rm -rf /tmp/calls-full.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath /tmp/calls-full.xcresult > /tmp/calls-full.log 2>&1` then the xcresulttool summary. Expected: `Passed`, 0 failed (previous full run: 144; the planner test file grows from 24 to 45 tests, plus 1 new sheet test, so about 166; report the exact total). Then run `grep -E "warning:" /tmp/calls-full.log | grep -E "ServerTwo/Voice/|ServerTwo/Scoring/(ScoringView|ScoringPromptSheet|MatchFormat\+LastGame).swift|AnnouncementPlannerTests.swift|ScoringPromptSheetTests.swift|ScoringPromptsUITests.swift"`: must be empty (report command and output).

- [ ] **Step 7: Append "As built" to the spec and commit**

Append to `docs/superpowers/specs/2026-10-17-official-calls-and-change-of-ends-design.md`:

```markdown

## As built

- `AnnouncementSnapshot.moveCount` (`currentGame.history.count`) distinguishes forward moves from undo; `AnnouncementPlanner.plan` composes prefix, call, switch line and stakes in that order; `pointStakes` requires the team to be strictly ahead after the point (the score check is symmetric) and uses serving-team-only eligibility for side-out and rally freeze, either team for rally without freeze.
- `MatchFormat.isLastGame(index:)` gates both the spoken "Switch sides."/"Switch back." and `ScoringView.syncSideSwitchPrompt`; in every other game no mid-game switch prompt or line is produced.
- The Game Over sheet shows a separate "Teams change ends." line above the unchanged "Next game starts at 0-0."; the spoken game line says "Change ends." before "Next game, ...".
- Match endings are "Game and match, <winner>, <w> to <l>." (best of 1) and "Game N to <winner>, <w> to <l>." + "Game and match, <winner>, <wg> games to <lg>." (best of 3/5).
- Not changed: initial service between games (Open question 2), still "winner serves first". (superseded: built in 2026-10-17-initial-service-alternation-design.md)
- Device checks owed: best of 3, game 1 passing 6 is silent and shows no sheet, game 3 passing 6 says "Switch sides." and shows the sheet; between games "Change ends." is spoken and shown; "Side out." on a side-out and "Second server." when the first server loses, neither after undo; "Game point." when serving at 10-8 (not when receiving at 8-10); "Match point." in a clincher; a game ending says "Game and match, ...".
```

```bash
git add ServerTwo/Scoring/ScoringView.swift ServerTwo/Scoring/ScoringPromptSheet.swift ServerTwoTests/ScoringPromptSheetTests.swift ServerTwoUITests/ScoringPromptsUITests.swift docs/superpowers/specs/2026-10-17-official-calls-and-change-of-ends-design.md
git commit -m "$(cat <<'EOF'
Mid-game Switch Sides only in the last game; Game Over says teams change ends

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Final report to the controller**

State the full-suite total, the warning-grep output, any Game Over detent change, and list the device checks from "As built" as NOT verified.
