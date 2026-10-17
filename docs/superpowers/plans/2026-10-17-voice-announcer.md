# Voice Announcer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Settings "Voice Announcer" toggle speak the pickleball score call after each score change, plus short event callouts (side switch, switch back, timeout, game over, match over), and make a downward score correction undo a side switch the same way undo does.

**Architecture:** A pure `AnnouncementPlanner` compares the previous and new `AnnouncementSnapshot` of the live match and returns the sentences to speak. `ScoringView` runs it from one `.onChange(of: snapshot)`. `VoiceAnnouncer` (toggle + VoiceOver checks) joins the sentences into one string and hands it to a `SpeechOutput`. `SystemSpeechOutput` owns the audio-session lifecycle (identity-checked callbacks, debounced deactivation) over thin AVFoundation adapters, so all of its logic is unit-tested with fakes. A small engine change makes `correctScores` recompute `hasSideSwitched`.

**Tech Stack:** Swift 5 language mode in the app target with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (types are `@MainActor` by default), SwiftUI/Observation, AVFoundation (`AVSpeechSynthesizer`, `AVAudioSession`), XCTest; PickleballKit is a Swift 6 package.

**Spec:** `docs/superpowers/specs/2026-10-16-voice-announcer-design.md` (approved by the user, including open question 5's default). Two small amendments made by this plan, to be recorded in the spec's "As built" section in Task 4: (1) `AnnouncementPlanner.plan` takes a `matchFormat` parameter (needed to word the best-of-1 match-over line); (2) the planner returns full sentences each ending in a period (`"4, 2, 1."`), which `VoiceAnnouncer` joins with a single space, so the single utterance pauses naturally between sentences.

## Global Constraints

- All new app code lives under `ServerTwo/Voice/` (the Xcode project uses file-system-synchronized groups, so new files are picked up automatically; do NOT hand-edit `project.pbxproj`). The only engine change is `PickleballGame.correctScores` (+ one doc comment); no other PickleballKit change.
- One announcement = ONE `AVSpeechUtterance`. Planner lines end with a period and are joined with `" "`.
- Audio session: category `.playback`, mode `.voicePrompt`, options `[.duckOthers, .interruptSpokenAudioAndMixWithOthers]`; deactivate with `.notifyOthersOnDeactivation` only after a 1.2 s quiet window; `preUtteranceDelay` 0.15 s when speech starts from an inactive session, 0 while the session is warm. Voice and rate: system defaults. No background-audio capability.
- Speech is silent when `appSettings.voiceAnnouncerEnabled` is false, when `UIAccessibility.isVoiceOverRunning`, on first appearance of the scoring screen (no `onChange` fire), and under UI tests (any launch argument starting with `-UITest-`).
- Speech stops when the toggle is turned off and when the scene leaves `.active`.
- `AVSpeechSynthesizerDelegate` methods are `nonisolated` and hop to the main actor carrying the utterance identity.
- Test conventions: PickleballKit tests via `swift test` from inside `PickleballKit/` (currently 156 XCTest tests; Swift Testing prints 0, ignore). App tests ONLY on the iOS 27 simulator `3C7D4B7A-F035-4AD7-89FF-B08256AF2516`, serially: `xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:<Target/Class> -resultBundlePath /tmp/<name>.xcresult`, verified ONLY with `xcrun xcresulttool get test-results summary --path /tmp/<name>.xcresult`. Never `name=iPhone 17 Pro`. If xcodebuild hangs 10+ minutes after a failure, `pkill -f xcodebuild` and rerun once; "Timed out while loading Accessibility" on a fresh sim means rerun. No `timeout` command on macOS. SourceKit shows false "No such module 'PickleballKit'" errors for new files; trust `xcodebuild`.
- Test classes that touch app types are marked `@MainActor`.
- Stage specific files only; NEVER stage `ServerTwo.xcodeproj/xcuserdata/**/xcschememanagement.plist`. Do not push. Commit messages end with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Keep UI test count unchanged (audio cannot be asserted); logic lives in fast unit tests.

## Review Focus

Failure modes the spec implies that are most likely to bite, each pinned to a test:

1. **Rapid scoring: a cancelled utterance's late `didCancel` must not kill the new utterance's session or schedule deactivation.** (Task 3: `testALateCallbackForACancelledUtteranceIsIgnored`, `testSpeakingDuringTheQuietWindowCancelsTheDeactivation`.)
2. **Team B winning a game or the match must speak the winner's score/games first** ("11 to 7", "2 to 1"), not Team A's. (Task 2: `testTeamBWinningAGameSpeaksTheWinnersScoreFirst`, `testTeamBClinchingASeriesSpeaksTheWinnersGamesFirst`.)
3. **A correction that crosses the side-switch threshold and completes the game in one change must speak only the game line**, not "Switch sides." (Task 2: `testGameCompletedWinsOverASideSwitchInTheSameChange`.)
4. **A downward correction under the threshold must clear the side switch and be undoable in one step.** (Task 1: engine tests + match test.)
5. **Nothing audible must be spoken when nothing changed, when a timeout is undone, or when the toggle is off / VoiceOver is running.** (Task 2: `testNoChangeIsSilent`, `testUndoingATimeoutIsSilent`; Task 3: `VoiceAnnouncerTests`.)
6. **UI tests must never touch the audio session.** (Task 4: the `-UITest-` prefix check and a grep that every UI test launch uses `-UITest-ResetState`.)

---

### Task 1: `correctScores` recomputes `hasSideSwitched` (PickleballKit)

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift` (`correctScores`, currently lines 164-170)
- Modify: `PickleballKit/Sources/PickleballKit/GameState.swift` (doc comment on `hasSideSwitched`, lines 8-12)
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballGameCorrectScoresTests.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballMatchCorrectScoresTests.swift`

**Interfaces:**
- Consumes: `WinningScore.sideSwitchThreshold` (`(rawValue + 1) / 2`: 6 / 8 / 11), `PickleballGame.correctScores(teamA:teamB:)`.
- Produces: unchanged signatures. New behavior: after `correctScores`, `state.hasSideSwitched == (max(teamAScore, teamBScore) >= threshold)`. `recordPoint` is unchanged (flag still only ever set false → true there; `checkSideSwitch()` stays for it). Undo still restores the whole previous `GameState`, flag included.

- [ ] **Step 1: Write the failing engine tests**

Append these tests inside `PickleballGameCorrectScoresTests` (it already has `makeGame(_:)` defaulting to an 11-point win-by-2 config, threshold 6), before the final closing brace:

```swift
    // MARK: - The side-switch flag follows the corrected score

    func testCorrectScoresBelowTheThresholdClearsASwitchThatAlreadyHappened() {
        let game = makeGame()  // threshold 6
        game.correctScores(teamA: 6, teamB: 2)
        XCTAssertTrue(game.state.hasSideSwitched)

        game.correctScores(teamA: 5, teamB: 2)
        XCTAssertFalse(game.state.hasSideSwitched)
    }

    func testCorrectScoresBackAcrossTheThresholdSwitchesAgain() {
        let game = makeGame()
        game.correctScores(teamA: 6, teamB: 2)
        game.correctScores(teamA: 5, teamB: 2)
        game.correctScores(teamA: 6, teamB: 2)
        XCTAssertTrue(game.state.hasSideSwitched)
    }

    func testCorrectScoresKeepsTheFlagWhileEitherTeamIsAtOrAboveTheThreshold() {
        let game = makeGame()
        game.correctScores(teamA: 8, teamB: 2)
        game.correctScores(teamA: 3, teamB: 6)   // Team B now carries it
        XCTAssertTrue(game.state.hasSideSwitched)
        game.correctScores(teamA: 8, teamB: 7)
        XCTAssertTrue(game.state.hasSideSwitched)
    }

    func testCorrectScoresUsesTheTargetsOwnThreshold() {
        // A game to 15 switches at 8.
        let game = makeGame(GameConfiguration(winningScore: .fifteen, winByTwo: true))
        game.correctScores(teamA: 7, teamB: 0)
        XCTAssertFalse(game.state.hasSideSwitched)
        game.correctScores(teamA: 8, teamB: 0)
        XCTAssertTrue(game.state.hasSideSwitched)
    }

    func testUndoingADownwardCorrectionRestoresTheSwitch() {
        let game = makeGame()
        game.correctScores(teamA: 6, teamB: 2)
        game.correctScores(teamA: 5, teamB: 2)
        XCTAssertFalse(game.state.hasSideSwitched)

        game.undo()
        XCTAssertTrue(game.state.hasSideSwitched)
        XCTAssertEqual(game.state.teamAScore, 6)
        XCTAssertEqual(game.state.teamBScore, 2)
    }
```

Append inside `PickleballMatchCorrectScoresTests` (it has `makeMatch(_:)`), before the final closing brace:

```swift
    func testADownwardCorrectionClearsTheSwitchFlagAndOneUndoRestoresIt() {
        let match = makeMatch(.bestOfThree)
        match.correctScores(teamA: 6, teamB: 2)
        XCTAssertTrue(match.currentGame.state.hasSideSwitched)

        match.correctScores(teamA: 5, teamB: 2)
        XCTAssertFalse(match.currentGame.state.hasSideSwitched)

        match.undo()
        XCTAssertTrue(match.currentGame.state.hasSideSwitched)
        XCTAssertEqual(match.currentGame.state.teamAScore, 6)
        XCTAssertEqual(match.currentGame.state.teamBScore, 2)
    }
```

- [ ] **Step 2: Run the new tests and confirm the right ones FAIL**

Run (from `/Users/delonsampaio/Desktop/VSCode Workspaces/ServerTwo/PickleballKit`): `swift test --filter "PickleballGameCorrectScoresTests|PickleballMatchCorrectScoresTests" 2>&1 | grep -E "error|failed|Executed" | head -20`
Expected: `testCorrectScoresBelowTheThresholdClearsASwitchThatAlreadyHappened`, `testCorrectScoresKeepsTheFlagWhileEitherTeamIsAtOrAboveTheThreshold` stays PASS (flag was true and stays true), `testUndoingADownwardCorrectionRestoresTheSwitch` FAILS on the `XCTAssertFalse` after the downward correction, `testADownwardCorrectionClearsTheSwitchFlagAndOneUndoRestoresIt` FAILS the same way. At least those three failures; if none fail, stop and investigate.

- [ ] **Step 3: Implement**

In `PickleballGame.swift` replace the body of `correctScores`:

```swift
    public func correctScores(teamA: Int, teamB: Int) {
        history.append(state)
        state.teamAScore = max(0, teamA)
        state.teamBScore = max(0, teamB)
        // Unlike `recordPoint` (scores only rise, so `checkSideSwitch` only ever
        // sets the flag), a correction can lower a score back under the
        // threshold, which undoes a switch that had already happened. Derive
        // the flag from the corrected scores so correcting down behaves like
        // undoing down.
        state.hasSideSwitched = max(state.teamAScore, state.teamBScore)
            >= configuration.winningScore.sideSwitchThreshold
        state.lastPointWonWhileServing = true
    }
```

In `GameState.swift` replace the doc comment above `public var hasSideSwitched: Bool` (lines 8-12) with:

```swift
    /// Set the first time either team's score reaches the game's side-switch
    /// threshold. Live scoring only ever raises it, so it stays `true` for the
    /// rest of the game; the two ways it goes back to `false` are `undo()`
    /// (which restores the whole earlier state) and a score correction that
    /// lowers both scores back under the threshold. UI code binding to it
    /// directly will keep showing an alert/notification state rather than
    /// firing once; callers needing a one-time notification must track their
    /// own "already acknowledged" state alongside this flag.
```

- [ ] **Step 4: Run all PickleballKit tests**

Run (from `PickleballKit/`): `swift test 2>&1 | grep -E "error|failed|Executed" | tail -4`
Expected: `Executed 162 tests, with 0 failures` (156 + 6 new). The pre-existing `testCorrectionThatCrossesTheSideSwitchThresholdAndEndsTheMatchLeavesBothFlagsSet` (11-9 → flag true) and `testCorrectScoreTriggersSideSwitchWhenCrossingTheThreshold` must still pass unchanged.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit/Sources/PickleballKit/PickleballGame.swift PickleballKit/Sources/PickleballKit/GameState.swift PickleballKit/Tests/PickleballKitTests/PickleballGameCorrectScoresTests.swift PickleballKit/Tests/PickleballKitTests/PickleballMatchCorrectScoresTests.swift
git commit -m "$(cat <<'EOF'
Make score correction recompute hasSideSwitched

A correction that lowers the score under the threshold now clears a switch
that had already happened (as undo does), so the Switch Back prompt and the
voice announcer cover corrections too.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `AnnouncementSnapshot` and `AnnouncementPlanner` (pure logic)

**Files:**
- Create: `ServerTwo/Voice/AnnouncementSnapshot.swift`
- Create: `ServerTwo/Voice/AnnouncementPlanner.swift`
- Test: `ServerTwoTests/AnnouncementPlannerTests.swift`

**Interfaces:**
- Consumes: `PickleballMatch` (`completedGames: [PickleballGame]`, `currentGame`, `gamesWon(for:)`, `isMatchOver`), `PickleballGame.state` (`GameState`), `PickleballGame.gameWinner: Team?`, `GameConfiguration` (`playMode`, `scoringFormat` which is `Equatable`: `.sideOut` / `.rally(freeze:)`), `MatchFormat`, `ServerNumber` (`.one` / `.two`, `rawValue` 1/2), `Team`.
- Produces (used by Tasks 3 and 4):
  - `struct AnnouncementSnapshot: Equatable` with memberwise init `AnnouncementSnapshot(gameIndex:teamAScore:teamBScore:servingTeam:serverNumber:hasSideSwitched:teamATimeoutsRemaining:teamBTimeoutsRemaining:teamAGamesWon:teamBGamesWon:isMatchOver:lastCompleted:)`, nested `struct CompletedGame: Equatable { teamAScore: Int; teamBScore: Int; winner: Team? }`, and `init(match: PickleballMatch)` (in an extension so the memberwise init stays available).
  - `enum AnnouncementPlanner` with `static func plan(from old: AnnouncementSnapshot, to new: AnnouncementSnapshot, configuration: GameConfiguration, matchFormat: MatchFormat, teamAName: String, teamBName: String) -> [String]` and `static func scoreCall(_ snapshot: AnnouncementSnapshot, configuration: GameConfiguration) -> String`.

- [ ] **Step 1: Write the failing tests**

Create `ServerTwoTests/AnnouncementPlannerTests.swift`:

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
        // One correction from 0-0 to 11-3: crosses the threshold AND ends the
        // game. The new game's flag is false and the game index moved, so only
        // the game lines apply.
        let old = snap(index: 0, a: 0, b: 0, switched: false)
        let new = snap(index: 1, a: 0, b: 0, switched: false, gamesA: 1,
                       last: .init(teamAScore: 11, teamBScore: 3, winner: .teamA))
        XCTAssertEqual(plan(old, new), ["Game 1 to Delon, 11 to 3.", "Next game, 0, 0, 2."])
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
```

- [ ] **Step 2: Run to verify it fails to compile (types do not exist)**

Run: `rm -rf /tmp/planner.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:ServerTwoTests/AnnouncementPlannerTests -resultBundlePath /tmp/planner.xcresult > /tmp/planner.log 2>&1; grep -E "error:" /tmp/planner.log | head -5`
Expected: errors such as "cannot find 'AnnouncementSnapshot' in scope".

- [ ] **Step 3: Implement the snapshot**

Create `ServerTwo/Voice/AnnouncementSnapshot.swift`:

```swift
import PickleballKit

/// The facts `AnnouncementPlanner` needs about the live match, captured as a
/// plain Equatable value so `ScoringView` can observe it with a single
/// `.onChange` and compare the previous and new state.
struct AnnouncementSnapshot: Equatable {
    /// `completedGames.count`: rises when a game finishes, falls when an undo
    /// reopens the previous game.
    var gameIndex: Int
    var teamAScore: Int
    var teamBScore: Int
    var servingTeam: Team
    var serverNumber: ServerNumber
    var hasSideSwitched: Bool
    var teamATimeoutsRemaining: Int
    var teamBTimeoutsRemaining: Int
    var teamAGamesWon: Int
    var teamBGamesWon: Int
    var isMatchOver: Bool
    /// Final score and winner of the most recently completed game, if any.
    var lastCompleted: CompletedGame?

    struct CompletedGame: Equatable {
        var teamAScore: Int
        var teamBScore: Int
        var winner: Team?
    }
}

extension AnnouncementSnapshot {
    init(match: PickleballMatch) {
        let state = match.currentGame.state
        self.init(
            gameIndex: match.completedGames.count,
            teamAScore: state.teamAScore,
            teamBScore: state.teamBScore,
            servingTeam: state.servingTeam,
            serverNumber: state.serverNumber,
            hasSideSwitched: state.hasSideSwitched,
            teamATimeoutsRemaining: state.teamATimeoutsRemaining,
            teamBTimeoutsRemaining: state.teamBTimeoutsRemaining,
            teamAGamesWon: match.gamesWon(for: .teamA),
            teamBGamesWon: match.gamesWon(for: .teamB),
            isMatchOver: match.isMatchOver,
            lastCompleted: match.completedGames.last.map {
                CompletedGame(
                    teamAScore: $0.state.teamAScore,
                    teamBScore: $0.state.teamBScore,
                    winner: $0.gameWinner
                )
            }
        )
    }
}
```

- [ ] **Step 4: Implement the planner**

Create `ServerTwo/Voice/AnnouncementPlanner.swift`:

```swift
import PickleballKit

/// Turns "what changed on the scoring screen" into the sentences to speak.
/// Pure and stateless. Every returned line is a full sentence ending in a
/// period; `VoiceAnnouncer` joins them with a space into one utterance.
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
                    return ["\(name(winner)) wins, \(winnerScore) to \(loserScore)."]
                }
                let matchWinner: Team = new.teamAGamesWon > new.teamBGamesWon ? .teamA : .teamB
                let winnerGames = matchWinner == .teamA ? new.teamAGamesWon : new.teamBGamesWon
                let loserGames = matchWinner == .teamA ? new.teamBGamesWon : new.teamAGamesWon
                return [
                    "Game \(new.gameIndex) to \(name(winner)), \(winnerScore) to \(loserScore).",
                    "\(name(matchWinner)) wins the match, \(winnerGames) to \(loserGames).",
                ]
            }
            return [
                "Game \(new.gameIndex) to \(name(winner)), \(winnerScore) to \(loserScore).",
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

        let callChanged = old.teamAScore != new.teamAScore
            || old.teamBScore != new.teamBScore
            || old.servingTeam != new.servingTeam
            || old.serverNumber != new.serverNumber
        if callChanged {
            lines.append(scoreCall(new, configuration: configuration) + ".")
        }
        if !old.hasSideSwitched && new.hasSideSwitched {
            lines.append("Switch sides.")
        } else if old.hasSideSwitched && !new.hasSideSwitched {
            lines.append("Switch back.")
        }
        return lines
    }

    /// Serving team's score, receiving team's score, then (doubles side-out
    /// only) the server number. Rally scoring and singles omit it.
    static func scoreCall(_ snapshot: AnnouncementSnapshot, configuration: GameConfiguration) -> String {
        let servingScore = snapshot.servingTeam == .teamA ? snapshot.teamAScore : snapshot.teamBScore
        let receivingScore = snapshot.servingTeam == .teamA ? snapshot.teamBScore : snapshot.teamAScore
        var parts = ["\(servingScore)", "\(receivingScore)"]
        if configuration.playMode == .doubles, configuration.scoringFormat == .sideOut {
            parts.append("\(snapshot.serverNumber.rawValue)")
        }
        return parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 5: Run the tests**

Run the same xcodebuild command as Step 2, then: `xcrun xcresulttool get test-results summary --path /tmp/planner.xcresult | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:d.get(k) for k in ('result','passedTests','failedTests','totalTestCount')})"`
Expected: `Passed`, 23 tests, 0 failed. If `testSnapshotReflectsALiveMatchAcrossAGameBoundary` fails because the serving team does not score from the first tap, check that `firstServingTeam: .teamA` scores on `recordPoint(for: .teamA)` (side-out: only the serving team scores) and fix the TEST's expectation, not the planner.

- [ ] **Step 6: Commit**

```bash
git add ServerTwo/Voice/AnnouncementSnapshot.swift ServerTwo/Voice/AnnouncementPlanner.swift ServerTwoTests/AnnouncementPlannerTests.swift
git commit -m "$(cat <<'EOF'
Add AnnouncementPlanner: pure score-call and event wording

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Speech output layer and `VoiceAnnouncer`

**Files:**
- Create: `ServerTwo/Voice/SpeechOutput.swift` (protocols + `NullSpeechOutput`)
- Create: `ServerTwo/Voice/SystemSpeechOutput.swift` (coordinator logic, scheduler, `live()` factory)
- Create: `ServerTwo/Voice/AVSpeechAdapters.swift` (`AVSpeechSynthesizerAdapter`, `AVAudioSessionController`; thin, no unit tests)
- Create: `ServerTwo/Voice/VoiceAnnouncer.swift`
- Test: `ServerTwoTests/SystemSpeechOutputTests.swift`
- Test: `ServerTwoTests/VoiceAnnouncerTests.swift`

**Interfaces:**
- Consumes: nothing from Task 2 (independent).
- Produces (used by Task 4; every callback/closure type is explicitly `@MainActor` so isolation does not depend on how the compiler infers it under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`):
  - `protocol SpeechOutput { func speak(_ text: String); func stop() }`; `struct NullSpeechOutput: SpeechOutput`.
  - `protocol SpeechSynthesizing: AnyObject { var onUtteranceEnded: ((UUID) -> Void)? { get set }; func speak(_ text: String, id: UUID, preDelay: TimeInterval); func stop() }`.
  - `protocol AudioSessionControlling { func activate(); func deactivate() }`.
  - `typealias DelayedActionScheduler = @MainActor (Duration, @escaping @MainActor () -> Void) -> () -> Void` (returns a cancel closure).
  - `final class SystemSpeechOutput: SpeechOutput` with `init(synthesizer:session:quietWindow:scheduler:)`, `static func live() -> SystemSpeechOutput`, `static let taskScheduler: DelayedActionScheduler`.
  - `@Observable final class VoiceAnnouncer` with `init(output: SpeechOutput, isEnabled: @escaping @MainActor () -> Bool, isVoiceOverRunning: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning })`, `func announce(_ lines: [String])`, `func stop()`.

- [ ] **Step 1: Write the failing tests**

Create `ServerTwoTests/SystemSpeechOutputTests.swift`:

```swift
import XCTest
@testable import ServerTwo

@MainActor
final class SystemSpeechOutputTests: XCTestCase {
    private final class FakeSynthesizer: SpeechSynthesizing {
        var onUtteranceEnded: (@MainActor (UUID) -> Void)?
        struct Spoken { let text: String; let id: UUID; let preDelay: TimeInterval }
        var spoken: [Spoken] = []
        var stopCount = 0
        func speak(_ text: String, id: UUID, preDelay: TimeInterval) {
            spoken.append(Spoken(text: text, id: id, preDelay: preDelay))
        }
        func stop() { stopCount += 1 }
    }

    private final class FakeSession: AudioSessionControlling {
        var activateCount = 0
        var deactivateCount = 0
        func activate() { activateCount += 1 }
        func deactivate() { deactivateCount += 1 }
    }

    /// Captures scheduled actions; `fire()` runs every one that was not cancelled.
    private final class FakeScheduler {
        private struct Entry { var action: @MainActor () -> Void; var done: Bool }
        private var entries: [Entry] = []
        /// Actions scheduled and neither cancelled nor run yet.
        var scheduledCount: Int { entries.filter { !$0.done }.count }
        func schedule(_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> () -> Void {
            entries.append(Entry(action: action, done: false))
            let index = entries.count - 1
            return { [unowned self] in self.entries[index].done = true }
        }
        func fire() {
            for index in entries.indices where !entries[index].done {
                entries[index].done = true
                entries[index].action()
            }
        }
    }

    private func makeOutput() -> (SystemSpeechOutput, FakeSynthesizer, FakeSession, FakeScheduler) {
        let synth = FakeSynthesizer()
        let session = FakeSession()
        let scheduler = FakeScheduler()
        let output = SystemSpeechOutput(
            synthesizer: synth, session: session, quietWindow: .seconds(1.2),
            scheduler: { delay, action in scheduler.schedule(delay, action) }
        )
        return (output, synth, session, scheduler)
    }

    func testTheFirstSpeakActivatesTheSessionWithALeadInAndALaterOneDoesNot() {
        let (output, synth, session, _) = makeOutput()
        output.speak("4, 2, 1.")
        XCTAssertEqual(session.activateCount, 1)
        XCTAssertEqual(synth.spoken[0].text, "4, 2, 1.")
        XCTAssertEqual(synth.spoken[0].preDelay, 0.15, accuracy: 0.0001)

        output.speak("5, 2, 1.")
        XCTAssertEqual(session.activateCount, 1, "the session is already warm")
        XCTAssertEqual(synth.spoken[1].preDelay, 0, accuracy: 0.0001)
    }

    func testSpeakingWhileAnotherUtteranceIsInFlightStopsItFirst() {
        let (output, synth, _, _) = makeOutput()
        output.speak("4, 2, 1.")
        XCTAssertEqual(synth.stopCount, 0)
        output.speak("5, 2, 1.")
        XCTAssertEqual(synth.stopCount, 1)
        XCTAssertEqual(synth.spoken.count, 2)
    }

    func testALateCallbackForACancelledUtteranceIsIgnored() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        let first = synth.spoken[0].id
        output.speak("5, 2, 1.")

        // The cancelled first utterance reports in AFTER the second started.
        synth.onUtteranceEnded?(first)
        XCTAssertEqual(scheduler.scheduledCount, 0, "a stale callback must not schedule deactivation")
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 0)
    }

    func testFinishingTheCurrentUtteranceDeactivatesOnlyAfterTheQuietWindow() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        synth.onUtteranceEnded?(synth.spoken[0].id)
        XCTAssertEqual(session.deactivateCount, 0, "not before the quiet window elapses")

        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 1)

        // The next call starts from an inactive session again.
        output.speak("5, 2, 1.")
        XCTAssertEqual(session.activateCount, 2)
        XCTAssertEqual(synth.spoken[1].preDelay, 0.15, accuracy: 0.0001)
    }

    func testSpeakingDuringTheQuietWindowCancelsTheDeactivation() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        synth.onUtteranceEnded?(synth.spoken[0].id)   // schedules deactivation
        output.speak("5, 2, 1.")                      // cancels it
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 0)
        XCTAssertEqual(session.activateCount, 1)
    }

    func testStopWhenNothingIsActiveDoesNothing() {
        let (output, synth, session, scheduler) = makeOutput()
        output.stop()
        XCTAssertEqual(synth.stopCount, 0)
        XCTAssertEqual(scheduler.scheduledCount, 0)
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 0)
        XCTAssertEqual(session.activateCount, 0)
    }

    func testStopCutsSpeechAndSchedulesDeactivation() {
        let (output, synth, session, scheduler) = makeOutput()
        output.speak("4, 2, 1.")
        output.stop()
        XCTAssertEqual(synth.stopCount, 1)
        // The cancel callback for the stopped utterance is stale (no current id).
        synth.onUtteranceEnded?(synth.spoken[0].id)
        scheduler.fire()
        XCTAssertEqual(session.deactivateCount, 1)
    }
}
```

Create `ServerTwoTests/VoiceAnnouncerTests.swift`:

```swift
import XCTest
@testable import ServerTwo

@MainActor
final class VoiceAnnouncerTests: XCTestCase {
    private final class RecordingOutput: SpeechOutput {
        var spoken: [String] = []
        var stopCount = 0
        func speak(_ text: String) { spoken.append(text) }
        func stop() { stopCount += 1 }
    }

    func testLinesAreJoinedIntoOneUtterance() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { true }, isVoiceOverRunning: { false })
        announcer.announce(["6, 3, 2.", "Switch sides."])
        XCTAssertEqual(output.spoken, ["6, 3, 2. Switch sides."])
    }

    func testNoLinesSpeaksNothing() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { true }, isVoiceOverRunning: { false })
        announcer.announce([])
        XCTAssertTrue(output.spoken.isEmpty)
    }

    func testADisabledToggleSpeaksNothing() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { false }, isVoiceOverRunning: { false })
        announcer.announce(["4, 2, 1."])
        XCTAssertTrue(output.spoken.isEmpty)
    }

    func testVoiceOverRunningSpeaksNothing() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { true }, isVoiceOverRunning: { true })
        announcer.announce(["4, 2, 1."])
        XCTAssertTrue(output.spoken.isEmpty)
    }

    func testTheToggleIsReadAtAnnounceTimeNotCapturedOnce() {
        let output = RecordingOutput()
        var enabled = true
        let announcer = VoiceAnnouncer(output: output, isEnabled: { enabled }, isVoiceOverRunning: { false })
        announcer.announce(["4, 2, 1."])
        enabled = false
        announcer.announce(["5, 2, 1."])
        XCTAssertEqual(output.spoken, ["4, 2, 1."])
    }

    func testStopForwardsToTheOutput() {
        let output = RecordingOutput()
        let announcer = VoiceAnnouncer(output: output, isEnabled: { true }, isVoiceOverRunning: { false })
        announcer.stop()
        XCTAssertEqual(output.stopCount, 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails to compile**

Run: `rm -rf /tmp/speech.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:ServerTwoTests/SystemSpeechOutputTests -only-testing:ServerTwoTests/VoiceAnnouncerTests -resultBundlePath /tmp/speech.xcresult > /tmp/speech.log 2>&1; grep -E "error:" /tmp/speech.log | head -5`
Expected: "cannot find type 'SpeechSynthesizing'" etc.

- [ ] **Step 3: Implement the protocols and the null output**

Create `ServerTwo/Voice/SpeechOutput.swift`:

```swift
import Foundation

/// Where an announcement's text goes. Real speech, or nothing (UI tests).
protocol SpeechOutput {
    func speak(_ text: String)
    func stop()
}

/// Used under UI tests so they never touch the audio session.
struct NullSpeechOutput: SpeechOutput {
    func speak(_ text: String) {}
    func stop() {}
}

/// Wraps `AVSpeechSynthesizer` so `SystemSpeechOutput`'s logic can be tested
/// with a fake. Reports the end of an utterance (finished OR cancelled) by id.
protocol SpeechSynthesizing: AnyObject {
    var onUtteranceEnded: (@MainActor (UUID) -> Void)? { get set }
    func speak(_ text: String, id: UUID, preDelay: TimeInterval)
    func stop()
}

/// Wraps `AVAudioSession` activation so `SystemSpeechOutput`'s logic can be
/// tested with a fake.
protocol AudioSessionControlling {
    func activate()
    func deactivate()
}

/// Schedules `action` after a delay and returns a closure that cancels it.
typealias DelayedActionScheduler = @MainActor (Duration, @escaping @MainActor () -> Void) -> () -> Void
```

- [ ] **Step 4: Implement `SystemSpeechOutput`**

Create `ServerTwo/Voice/SystemSpeechOutput.swift`:

```swift
import Foundation

/// Speaks announcements and owns the audio-session lifecycle.
///
/// Two races this exists to avoid (see the design spec):
/// - `stopSpeaking(.immediate)` then a new `speak` means the cancelled
///   utterance's `didCancel` can arrive AFTER the new utterance started. Every
///   callback is therefore checked against the current utterance's id and
///   ignored when it is stale.
/// - Deactivating the session after every utterance makes background music
///   pump up and down between rapid calls and tears down a warm Bluetooth
///   route. Deactivation is debounced by a quiet window and cancelled by the
///   next `speak`.
final class SystemSpeechOutput: SpeechOutput {
    private let synthesizer: SpeechSynthesizing
    private let session: AudioSessionControlling
    private let quietWindow: Duration
    private let scheduler: DelayedActionScheduler

    private var currentID: UUID?
    private var sessionActive = false
    private var cancelPendingDeactivation: (() -> Void)?

    /// Lead-in when speech starts from an inactive session, so a waking
    /// Bluetooth route does not swallow the first number.
    private let coldStartDelay: TimeInterval = 0.15

    init(
        synthesizer: SpeechSynthesizing,
        session: AudioSessionControlling,
        quietWindow: Duration = .seconds(1.2),
        scheduler: @escaping DelayedActionScheduler = SystemSpeechOutput.taskScheduler
    ) {
        self.synthesizer = synthesizer
        self.session = session
        self.quietWindow = quietWindow
        self.scheduler = scheduler
        synthesizer.onUtteranceEnded = { [weak self] id in
            self?.utteranceEnded(id)
        }
    }

    static func live() -> SystemSpeechOutput {
        SystemSpeechOutput(
            synthesizer: AVSpeechSynthesizerAdapter(),
            session: AVAudioSessionController()
        )
    }

    static let taskScheduler: DelayedActionScheduler = { delay, action in
        let task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { action() }
        }
        return { task.cancel() }
    }

    func speak(_ text: String) {
        cancelPendingDeactivation?()
        cancelPendingDeactivation = nil
        if currentID != nil { synthesizer.stop() }

        let preDelay: TimeInterval = sessionActive ? 0 : coldStartDelay
        if !sessionActive {
            session.activate()
            sessionActive = true
        }
        let id = UUID()
        currentID = id
        synthesizer.speak(text, id: id, preDelay: preDelay)
    }

    func stop() {
        // Nothing spoken since the session was last released: leave the audio
        // session alone (scene-phase changes call this on every backgrounding).
        guard sessionActive else { return }
        synthesizer.stop()
        currentID = nil
        scheduleDeactivation()
    }

    private func utteranceEnded(_ id: UUID) {
        guard id == currentID else { return }   // stale callback
        currentID = nil
        scheduleDeactivation()
    }

    private func scheduleDeactivation() {
        cancelPendingDeactivation?()
        cancelPendingDeactivation = scheduler(quietWindow) { [weak self] in
            guard let self else { return }
            self.session.deactivate()
            self.sessionActive = false
            self.cancelPendingDeactivation = nil
        }
    }
}
```

- [ ] **Step 5: Implement the AVFoundation adapters**

Create `ServerTwo/Voice/AVSpeechAdapters.swift`:

```swift
import AVFoundation

/// Thin `AVSpeechSynthesizer` wrapper. No logic beyond mapping utterances to
/// the ids `SystemSpeechOutput` tracks; verified on a device, not in unit
/// tests. The project builds with MainActor default isolation, and
/// `AVSpeechSynthesizerDelegate` is not main-actor isolated, so the delegate
/// methods are `nonisolated` and hop back carrying only the utterance's
/// `ObjectIdentifier`.
final class AVSpeechSynthesizerAdapter: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    var onUtteranceEnded: (@MainActor (UUID) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var ids: [ObjectIdentifier: UUID] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, id: UUID, preDelay: TimeInterval) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.preUtteranceDelay = preDelay
        ids[ObjectIdentifier(utterance)] = id
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(key) }
    }

    private func ended(_ key: ObjectIdentifier) {
        guard let id = ids.removeValue(forKey: key) else { return }
        onUtteranceEnded?(id)
    }
}

/// `.playback` plays through the silent switch and to Bluetooth; `.voicePrompt`
/// is the mode for brief spoken prompts; ducking lowers music and
/// `.interruptSpokenAudioAndMixWithOthers` pauses podcasts/audiobooks for the
/// call instead of talking over them. The category is set once, lazily.
final class AVAudioSessionController: AudioSessionControlling {
    private var configured = false

    func activate() {
        let session = AVAudioSession.sharedInstance()
        if !configured {
            try? session.setCategory(
                .playback, mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            configured = true
        }
        try? session.setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
```

If the compiler reports an actor-isolation error on a delegate method or the `Task` capture under the project's MainActor-default isolation, make the MINIMAL change that compiles (keep the methods `nonisolated`, keep carrying only `ObjectIdentifier`), and record what you changed in the report.

- [ ] **Step 6: Implement `VoiceAnnouncer`**

Create `ServerTwo/Voice/VoiceAnnouncer.swift`:

```swift
import Observation
import UIKit

/// The single place the "should we speak at all" checks live. Owned by
/// `MyApp`, injected through the environment.
@Observable
final class VoiceAnnouncer {
    @ObservationIgnored private let output: SpeechOutput
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private let isVoiceOverRunning: @MainActor () -> Bool

    init(
        output: SpeechOutput,
        isEnabled: @escaping @MainActor () -> Bool,
        isVoiceOverRunning: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }
    ) {
        self.output = output
        self.isEnabled = isEnabled
        self.isVoiceOverRunning = isVoiceOverRunning
    }

    /// `lines` are the planner's sentences. They are joined into ONE utterance
    /// so a single announcement never has more than one utterance in flight.
    /// VoiceOver already reads the score zones' label changes, so the
    /// announcer stays silent when it is running.
    func announce(_ lines: [String]) {
        guard !lines.isEmpty, isEnabled(), !isVoiceOverRunning() else { return }
        output.speak(lines.joined(separator: " "))
    }

    func stop() {
        output.stop()
    }
}
```

- [ ] **Step 7: Run the tests**

Run the Step 2 command again, then check with xcresulttool (see Task 2 Step 5).
Expected: `Passed`, 13 tests (7 + 6), 0 failed. The app target must also build: no other file references these types yet.

- [ ] **Step 8: Commit**

```bash
git add ServerTwo/Voice/SpeechOutput.swift ServerTwo/Voice/SystemSpeechOutput.swift ServerTwo/Voice/AVSpeechAdapters.swift ServerTwo/Voice/VoiceAnnouncer.swift ServerTwoTests/SystemSpeechOutputTests.swift ServerTwoTests/VoiceAnnouncerTests.swift
git commit -m "$(cat <<'EOF'
Add speech output layer and VoiceAnnouncer

Identity-checked callbacks and debounced audio-session deactivation, over
thin AVFoundation adapters; one utterance per announcement.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Wire it into the app, then verify

**Files:**
- Modify: `ServerTwo/MyApp.swift` (create the announcer, inject it, stop on toggle-off and on leaving `.active`)
- Modify: `ServerTwo/Scoring/ScoringView.swift` (observe the snapshot, announce)
- Modify: `docs/superpowers/specs/2026-10-16-voice-announcer-design.md` (append an `## As built` section)

**Interfaces:**
- Consumes: Task 2 (`AnnouncementSnapshot(match:)`, `AnnouncementPlanner.plan`), Task 3 (`VoiceAnnouncer`, `SystemSpeechOutput.live()`, `NullSpeechOutput`), `AppSettings.voiceAnnouncerEnabled`, `ActiveMatchController.match / teamAName / teamBName`, `PickleballMatch.configuration / matchFormat`.
- Produces: the feature, end to end.

- [ ] **Step 1: Verify the UI-test launch assumption**

Run: `grep -L "UITest-ResetState" ServerTwoUITests/*UITests.swift`
Expected: no output (every UI test file mentions it). The null output keys off ANY launch argument with the `-UITest-` prefix, so even a file listed here is covered as long as it passes some `-UITest-*` argument; if a UI test passes none, add `-UITest-ResetState` to its `launchArguments`.

- [ ] **Step 2: Wire `MyApp`**

In `ServerTwo/MyApp.swift`:

1. Replace `@State private var appSettings = AppSettings()` with:

```swift
    @State private var appSettings: AppSettings
    @State private var voiceAnnouncer: VoiceAnnouncer
    @Environment(\.scenePhase) private var scenePhase
```

2. In `init()`, after `self.modelContainer = container` and the existing `_activeMatchController = ...` line, add:

```swift
        let settings = AppSettings()
        _appSettings = State(initialValue: settings)
        _voiceAnnouncer = State(initialValue: VoiceAnnouncer(
            output: MyApp.makeSpeechOutput(),
            isEnabled: { settings.voiceAnnouncerEnabled }
        ))
```

3. Add this method next to `applyTestOverridesIfNeeded`:

```swift
    /// UI tests must never touch the audio session: any `-UITest-` launch
    /// argument (Debug builds only) swaps real speech for a no-op output.
    private static func makeSpeechOutput() -> SpeechOutput {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-UITest-") }) {
            return NullSpeechOutput()
        }
        #endif
        return SystemSpeechOutput.live()
    }
```

4. In `body`, add to the `RootTabView(...)` modifier chain, right after `.environment(appSettings)`:

```swift
                .environment(voiceAnnouncer)
                .onChange(of: appSettings.voiceAnnouncerEnabled) { _, enabled in
                    if !enabled { voiceAnnouncer.stop() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { voiceAnnouncer.stop() }
                }
```

(The toggle-off stop lives here, not in `ScoringView`, because the Scoring screen is not on screen while the user is in Settings.)

- [ ] **Step 3: Wire `ScoringView`**

In `ServerTwo/Scoring/ScoringView.swift`:

1. Next to the other `@Environment` properties add: `@Environment(VoiceAnnouncer.self) private var voiceAnnouncer`.

2. Add this modifier to `body`'s chain, immediately before the existing `.onChange(of: activeMatchController.match?.completedGames.count)` handler:

```swift
        .onChange(of: activeMatchController.match.map(AnnouncementSnapshot.init(match:))) { old, new in
            // `onChange` does not fire for the initial value, so a resumed match
            // stays silent until its next change. Derived from state (not from
            // which button was pressed) so taps, undo, a Correct Score save and
            // accessibility actions all announce the same way.
            guard let match = activeMatchController.match, let old, let new else { return }
            voiceAnnouncer.announce(AnnouncementPlanner.plan(
                from: old, to: new,
                configuration: match.configuration, matchFormat: match.matchFormat,
                teamAName: activeMatchController.teamAName,
                teamBName: activeMatchController.teamBName
            ))
        }
```

- [ ] **Step 4: Build and run the full app suite**

Run: `rm -rf /tmp/voice-full.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath /tmp/voice-full.xcresult > /tmp/voice-full.log 2>&1; xcrun xcresulttool get test-results summary --path /tmp/voice-full.xcresult | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:d.get(k) for k in ('result','passedTests','failedTests','skippedTests','totalTestCount')})"`
Expected: `Passed`, 0 failed. The previous full run had 94 tests; this plan adds 36 (23 planner + 7 coordinator + 6 announcer), plus the ones from the polish commit (`TapOrHoldModifierTests`), so report the exact total. All existing UI tests (golden path, score correction, scoring prompts, Quick Log, gestures) must pass unchanged. Also run PickleballKit once more: from `PickleballKit/`, `swift test 2>&1 | grep -E "Executed|error" | tail -2` → 162 tests, 0 failures.

- [ ] **Step 5: Append "As built" to the spec**

Append to `docs/superpowers/specs/2026-10-16-voice-announcer-design.md`:

```markdown

## As built

- `AnnouncementPlanner.plan` also takes `matchFormat` (needed for the best-of-1 match-over line), and returns full sentences ending in a period; `VoiceAnnouncer` joins them with a space into one utterance.
- Open question 5 resolved: `PickleballGame.correctScores` now derives `hasSideSwitched` from the corrected scores (flag = max score ≥ threshold), so a downward correction clears a switch like undo does; undo restores the flag.
- New code is under `ServerTwo/Voice/`: `AnnouncementSnapshot`, `AnnouncementPlanner`, `SpeechOutput` (+ `NullSpeechOutput`), `SystemSpeechOutput` (identity-checked callbacks, 1.2 s debounced deactivation, 0.15 s cold-start lead-in), `AVSpeechAdapters` (device-verified only), `VoiceAnnouncer`.
- `MyApp` owns the announcer, stops speech when the toggle turns off or the scene leaves `.active`, and uses `NullSpeechOutput` for any `-UITest-` launch argument in Debug builds. `ScoringView` runs the planner from one `.onChange` on the snapshot.
- Device checks still owed (not verifiable in the simulator): calls audible in a doubles game; "Switch sides." / "Switch back." / "Timeout, <team>." / game and match lines; music ducks and returns; a podcast pauses and resumes; AirPods/Bluetooth first number not clipped; silent switch on still speaks; toggle off silences; a resumed match is silent until the next change; VoiceOver on = silent; a downward Correct Score edit under the threshold is spoken ("... Switch back.") and shows the Switch Back sheet after the Correct Score sheet closes.
```

- [ ] **Step 6: Commit**

```bash
git add ServerTwo/MyApp.swift ServerTwo/Scoring/ScoringView.swift docs/superpowers/specs/2026-10-16-voice-announcer-design.md
git commit -m "$(cat <<'EOF'
Wire the Voice Announcer into the scoring screen

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 7: Final report to the controller**

State the full-suite and PickleballKit totals, list anything you changed from this plan with the reason (especially any actor-isolation adjustment in `AVSpeechAdapters.swift`), and list the device checks from the "As built" section as NOT verified.
