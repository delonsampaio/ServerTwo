# Initial Service Alternation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The next game's first server is the opponent of the previous game's first server (official Rule 21.F.2), not the previous winner; the app says who serves first (Game Over sheet and spoken line), and the announcer names the new serving team after a side-out.

**Architecture:** A derived, read-only `PickleballGame.initialServingTeam` (`history.first?.servingTeam ?? state.servingTeam`) feeds the two next-game creation sites in `PickleballMatch`; no stored field, no Codable change. The announcer's pure planner and the Game Over prompt/sheet gain the serving-team wording. Existing multi-game tests that assumed "winner serves next" are updated through a shared "play out a game" helper that does not assume who serves.

**Tech Stack:** Swift 6 package PickleballKit (XCTest, `swift test`), Swift 5-mode SwiftUI app target with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, XCTest/XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-17-initial-service-alternation-design.md` (approved by the user; Gemini-reviewed and corrected). Builds on `2026-10-17-official-calls-and-change-of-ends-design.md`.

## Global Constraints

- Rule citation allowed in code/docs: Rule 21.F.2 only (and Rule 21.F.3 as "out of scope"). No other rule numbers.
- No stored field and no Codable change: `initialServingTeam` is a computed property on `PickleballGame`. `MatchSnapshot` is untouched.
- The two next-game creation sites in `PickleballMatch` (`recordPoint(for:)` and `reconcileCurrentGame(wasCounted:previousWinner:)`) both use `currentGame.initialServingTeam.opponent` (evaluated on the game being archived, before `currentGame` is reassigned). Nothing else in the engine changes. `undo()` Branch 3's documented limitation stays out of scope.
- Spoken wording (planner lines are sentences ending in a period, joined with a space): side-out in side-out scoring on a forward move: `["Side out.", "<new serving team> serving.", "<call>."]`; "Second server." unchanged (no team name); next game: `"Next game, <first server> serving, <call>."`; between games the existing `"Switch sides."` line stays. Names are spoken as entered.
- Game Over sheet gets a separate text element `"First serve: <name>."` between the existing "Teams switch sides." and "Next game starts at 0-0." elements. The Game Over prompt's new associated value `firstServerName` is read from `match.currentGame.state.servingTeam` at prompt creation (that game is already the freshly created next game).
- Test conventions: PickleballKit tests via `swift test` from inside `PickleballKit/` (currently 162 XCTest tests; Swift Testing prints 0, ignore). App tests ONLY on the iOS 27 simulator `3C7D4B7A-F035-4AD7-89FF-B08256AF2516` (if shut down: `xcrun simctl boot 3C7D4B7A-F035-4AD7-89FF-B08256AF2516`), serially: `xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:<Target/Class> -resultBundlePath /tmp/<name>.xcresult`, verified ONLY with `xcrun xcresulttool get test-results summary --path /tmp/<name>.xcresult` (print `result, passedTests, failedTests, totalTestCount`). Never `name=iPhone 17 Pro`. If xcodebuild hangs 10+ minutes after a failure, `pkill -f xcodebuild` and rerun once; "Timed out while loading Accessibility" means rerun. No `timeout` command on macOS. SourceKit shows false "No such module" errors; trust the build.
- Test classes that touch app types are `@MainActor`. Existing tests are updated by PRESERVING their intent; never delete or weaken an assertion silently; every changed test is listed in the report with the reason.
- Output must be pristine: after the full-suite run, grep a FRESH compile log (confirm `grep -c "SwiftCompile.*<file>"` is at least 1 for edited app files; if a run reused old products, touch the edited files and rebuild) for warnings from changed files.
- Stage specific files only; NEVER stage `ServerTwo.xcodeproj/xcuserdata/**/xcschememanagement.plist`. Do not push. Commit messages end with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Between Task 1 and Task 3 the app-target unit tests that play multi-game matches (`ActiveMatchControllerTests` and similar) are expected to fail until Task 3 updates them; Task 1 and Task 2 only need their own targeted tests green.

## Review Focus

1. **First server independent of the winner:** a game won by the first server's opponent and by the first server both give the same next first server, including via correction. (Task 1: `testWhoWonThePreviousGameDoesNotDecideTheNextFirstServer`, `testACorrectionThatEndsAGameGivesTheNextGameToTheFirstServersOpponent`.)
2. **Derivation survives every history state:** fresh, after moves, all undone, correction, snapshot round trip, undo-then-replay, and a match saved under the old rule. (Task 1.)
3. **No existing multi-game test is weakened:** each is updated to the same intent through `playOutGame`; the assertions that said "winner serves next game" now say alternation with the rule named. (Tasks 1 and 3.)
4. **"Side out." names the NEW server, forward moves only:** not after undo, not in rally, no name on "Second server.". (Task 2.)
5. **The Game Over prompt and sheet name the NEXT game's first server (not the winner):** read from the new `currentGame`. (Tasks 2 and 3.)

---

### Task 1: Engine alternation and PickleballKit tests

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift` (add `initialServingTeam`)
- Modify: `PickleballKit/Sources/PickleballKit/PickleballMatch.swift` (`recordPoint`, `reconcileCurrentGame`)
- Create: `PickleballKit/Tests/PickleballKitTests/MatchTestSupport.swift`
- Create: `PickleballKit/Tests/PickleballKitTests/PickleballMatchInitialServiceTests.swift`
- Modify: `PickleballKit/Tests/PickleballKitTests/PickleballMatchTests.swift`, `PickleballMatchCorrectScoresTests.swift`, `PickleballMatchRehydrationTests.swift`, and any other PickleballKit test that fails after the engine change

**Interfaces:**
- Consumes: `PickleballGame.history`, `PickleballGame.state`, `Team.opponent`, `PickleballMatch.snapshot(startedAt:)`, `PickleballMatch(resuming:proUnlocked:demoPointCap:)`, the restoring `PickleballMatch.init(configuration:matchFormat:completedGames:currentGame:gamesWon:currentGameIsCounted:)`.
- Produces: `PickleballGame.initialServingTeam: Team` (public, read-only, computed); the global test helper `playOutGame(_:winner:file:line:)` in the PickleballKit test target (used by Task 1's updated tests).

- [ ] **Step 1: Write the shared helper and the failing tests**

Create `PickleballKit/Tests/PickleballKitTests/MatchTestSupport.swift`:

```swift
import XCTest
@testable import PickleballKit

/// Plays out one whole game for `winner` without assuming who serves first:
/// in side-out scoring only the serving team scores, so a winner who is
/// receiving first has to win the side-outs. Taps the winner's `recordPoint`
/// until the match archives one more game (bounded, so a bug fails instead of
/// hanging).
func playOutGame(
    _ match: PickleballMatch,
    winner: Team,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let target = match.completedGames.count + 1
    var taps = 0
    while match.completedGames.count < target, taps < 200 {
        match.recordPoint(for: winner)
        taps += 1
    }
    XCTAssertEqual(match.completedGames.count, target, "the game never finished for \(winner)", file: file, line: line)
}
```

Create `PickleballKit/Tests/PickleballKitTests/PickleballMatchInitialServiceTests.swift`:

```swift
import XCTest
@testable import PickleballKit

/// Rule 21.F.2: teams change ends AND initial service for the next game, so the
/// first server alternates every game and never depends on who won.
final class PickleballMatchInitialServiceTests: XCTestCase {
    private func makeMatch(
        _ format: MatchFormat = .bestOfThree,
        first: Team = .teamA,
        config: GameConfiguration = GameConfiguration()
    ) -> PickleballMatch {
        PickleballMatch(configuration: config, matchFormat: format, firstServingTeam: first, proUnlocked: true, demoPointCap: nil)
    }

    func testInitialServiceAlternatesAcrossABestOfThree() {
        let match = makeMatch(first: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA)

        playOutGame(match, winner: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "the other team serves first in game 2")
        XCTAssertEqual(match.currentGame.state.servingTeam, .teamB)

        playOutGame(match, winner: .teamB)   // 1-1
        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA, "game 3 starts with game 1's first server")
    }

    func testStartingWithTeamBAlternatesTheSameWay() {
        let match = makeMatch(first: .teamB)
        playOutGame(match, winner: .teamB)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA)
        playOutGame(match, winner: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB)
    }

    func testWhoWonThePreviousGameDoesNotDecideTheNextFirstServer() {
        for winner in Team.allCases {
            let match = makeMatch(first: .teamA)
            playOutGame(match, winner: winner)
            XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "game 1 won by \(winner)")
        }
    }

    func testABestOfFiveAlternatesEveryGame() {
        let match = makeMatch(.bestOfFive, first: .teamA)
        let winners: [Team] = [.teamA, .teamB, .teamA, .teamB]
        let expectedFirst: [Team] = [.teamB, .teamA, .teamB, .teamA]
        for (winner, expected) in zip(winners, expectedFirst) {
            playOutGame(match, winner: winner)
            XCTAssertFalse(match.isMatchOver)
            XCTAssertEqual(match.currentGame.initialServingTeam, expected)
        }
    }

    func testSinglesAndRallyScoringAlternateToo() {
        let configs = [
            GameConfiguration(playMode: .singles, scoringFormat: .sideOut),
            GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: false)),
            GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: true)),
        ]
        for config in configs {
            let match = makeMatch(first: .teamA, config: config)
            playOutGame(match, winner: .teamA)
            XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "\(config.scoringFormat) \(config.playMode)")
        }
    }

    func testInitialServingTeamSurvivesMovesCorrectionAndUndo() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertEqual(game.initialServingTeam, .teamA)

        game.recordPoint(for: .teamB)   // doubles 0-0-2: B wins the rally, a full side-out
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.initialServingTeam, .teamA, "the first history entry is the state before the first move")

        game.correctScores(teamA: 5, teamB: 3)
        XCTAssertEqual(game.initialServingTeam, .teamA)

        game.undo()
        game.undo()
        XCTAssertFalse(game.canUndo)
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.initialServingTeam, .teamA, "with every move undone the state itself is the initial state")
    }

    func testACorrectionThatEndsAGameGivesTheNextGameToTheFirstServersOpponent() {
        for (a, b) in [(11, 9), (9, 11)] {
            let match = makeMatch(first: .teamA)
            match.correctScores(teamA: a, teamB: b)
            XCTAssertEqual(match.completedGames.count, 1, "\(a)-\(b)")
            XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "\(a)-\(b): not the winner")
        }
    }

    func testFlippingTheWinnerOfADecidedGameStillAlternates() {
        // Engine-only path (the UI disables scoring once the match is over).
        let match = makeMatch(first: .teamA)
        playOutGame(match, winner: .teamA)    // game 1; game 2 starts with B serving
        playOutGame(match, winner: .teamA)    // game 2: A wins, match over 2-0
        XCTAssertTrue(match.isMatchOver)

        match.correctScores(teamA: 0, teamB: 11)   // game 2 now belongs to B: 1-1, game 3 created

        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.completedGames.count, 2)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA, "game 2's first server was B, so game 3 starts with A")
    }

    func testUndoingAGameEndingPointAndReplayingGivesTheSameNextFirstServer() {
        let match = makeMatch(first: .teamA)
        playOutGame(match, winner: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB)

        match.undo()   // reopens game 1 one point before the end
        XCTAssertTrue(match.completedGames.isEmpty)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA)

        playOutGame(match, winner: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB)
    }

    func testAResumedMatchKeepsAlternating() {
        let match = makeMatch(first: .teamA)
        playOutGame(match, winner: .teamA)
        let snapshot = match.snapshot(startedAt: Date(timeIntervalSince1970: 0))

        let resumed = PickleballMatch(resuming: snapshot, proUnlocked: true, demoPointCap: nil)
        XCTAssertEqual(resumed.currentGame.initialServingTeam, .teamB)

        playOutGame(resumed, winner: .teamB)   // 1-1
        XCTAssertEqual(resumed.currentGame.initialServingTeam, .teamA)
    }

    func testAMatchSavedUnderTheOldWinnerServesRuleFollowsTheStoredGameFromThenOn() {
        // Old build: game 1 started with A and A won; game 2 started with the
        // winner (A) serving. Only games created after the upgrade follow the
        // new rule, derived from game 2's stored first server.
        let config = GameConfiguration()
        let game1 = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { game1.recordPoint(for: .teamA) }
        let game2 = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        let match = PickleballMatch(
            configuration: config, matchFormat: .bestOfThree,
            completedGames: [game1], currentGame: game2,
            gamesWon: [.teamA: 1, .teamB: 0], currentGameIsCounted: false
        )

        playOutGame(match, winner: .teamB)   // 1-1
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "game 2 began with A serving, so game 3 begins with B")
    }
}
```

- [ ] **Step 2: Run to verify it fails to compile**

Run (from `/Users/delonsampaio/Desktop/VSCode Workspaces/ServerTwo/PickleballKit`): `swift test --filter PickleballMatchInitialServiceTests 2>&1 | grep -E "error:" | head -5`
Expected: `value of type 'PickleballGame' has no member 'initialServingTeam'`.

- [ ] **Step 3: Implement**

In `PickleballKit/Sources/PickleballKit/PickleballGame.swift`, directly after `public var canUndo: Bool { !history.isEmpty }`, add:

```swift
    /// Who served first in this game. Every move appends the state BEFORE the
    /// move to `history`, so its first element is the game's initial state and
    /// its `servingTeam` is the initial server; a game with no moves (or with
    /// every move undone) still has it in `state`. Derived, not stored: no
    /// Codable change, and it works for games saved by earlier builds. The next
    /// game's first server is this team's opponent (Rule 21.F.2).
    public var initialServingTeam: Team {
        history.first?.servingTeam ?? state.servingTeam
    }
```

In `PickleballKit/Sources/PickleballKit/PickleballMatch.swift`, in `recordPoint(for:)` replace

```swift
        currentGame = PickleballGame(
            configuration: configuration,
            firstServingTeam: winner,
            proUnlocked: currentGame.proUnlocked,
            demoPointCap: currentGame.demoPointCap
        )
```

with

```swift
        // Initial service changes every game (Rule 21.F.2): the other team
        // serves first, whoever won this one.
        currentGame = PickleballGame(
            configuration: configuration,
            firstServingTeam: currentGame.initialServingTeam.opponent,
            proUnlocked: currentGame.proUnlocked,
            demoPointCap: currentGame.demoPointCap
        )
```

and in `reconcileCurrentGame(wasCounted:previousWinner:)` replace

```swift
                currentGame = PickleballGame(
                    configuration: configuration,
                    firstServingTeam: newWinner,
                    proUnlocked: currentGame.proUnlocked,
                    demoPointCap: currentGame.demoPointCap
                )
```

with

```swift
                // Rule 21.F.2: the first server alternates and does not depend
                // on who won (a correction can flip the winner).
                currentGame = PickleballGame(
                    configuration: configuration,
                    firstServingTeam: currentGame.initialServingTeam.opponent,
                    proUnlocked: currentGame.proUnlocked,
                    demoPointCap: currentGame.demoPointCap
                )
```

(In both sites `currentGame` on the right-hand side is still the game being archived, because the expression is evaluated before the assignment.)

- [ ] **Step 4: Run the new tests, then the whole PickleballKit suite**

Run: `swift test --filter PickleballMatchInitialServiceTests 2>&1 | grep -E "error|failed|Executed" | tail -4`
Expected: `Executed 11 tests, with 0 failures`.

Then run all: `swift test 2>&1 | grep -E "error:|failed|Executed" | tail -20`
Expected: the new 11 pass and SOME EXISTING tests now fail because they assumed the winner serves next. Known ones: `PickleballMatchTests` `testWinningAGameAdvancesToANewGameWithWinnerServingFirst` (asserts `.teamA` serves game 2) and the correct-score variant at ~line 107 (`// winner serves next game`), `testWinningEnoughGamesEndsTheMatch` (plays game 2 with 11 taps for Team A), `PickleballMatchCorrectScoresTests` (`testCorrectionThatCompletesANonFinalGameArchives...` asserts `.teamA` serves game 2 at ~line 56; its siblings that play game 2 with `for _ in 1...11 { match.recordPoint(for: .teamA) }` at ~lines 70, 94, 122, 140, 159) and `PickleballMatchRehydrationTests` (its `original.recordPoint(for: .teamB)` after game 1 assumed Team A serves game 2; with Team B serving it is now a SCORE, not a side-out; keep the test's intent, "a side-out, not a score", by tapping `.teamA` instead and adjust only what that implies). Find the rest by running the suite.

- [ ] **Step 5: Update the existing tests (intent preserved)**

For every failing test:
- Where a test plays a later game by looping `for _ in 1...11 { X.recordPoint(for: .teamA) }`, replace that loop with `playOutGame(X, winner: .teamA)` (the helper handles whoever serves). Game-1 loops (Team A first via `firstServingTeam: .teamA`) stay as they are.
- Where a test asserts the winner serves the next game (`XCTAssertEqual(match.currentGame.state.servingTeam, .teamA) // winner serves next game`), change the expectation to `.teamB` and the comment to `// Rule 21.F.2: the other team serves first, not the winner`, and rename the test (for example `testWinningAGameAdvancesToANewGameWithTheOtherTeamServingFirst`).
- Where a count of taps matters to the assertion (undo counts, history lengths), keep the assertion's intent and adjust the number to the real tap count the helper plays; explain it in a comment.
- Do NOT delete an assertion or change what a test verifies. List every changed test, old behavior and new behavior, in your report.

- [ ] **Step 6: Run everything and commit**

Run `swift test 2>&1 | grep -E "error:|failed|Executed" | tail -4` (from `PickleballKit/`). Expected: `Executed 173 tests, with 0 failures` (162 + 11), with no warnings from the changed files (`swift test 2>&1 | grep -i "warning:" | grep -E "PickleballGame|PickleballMatch|MatchTestSupport"` is empty).

```bash
git add PickleballKit/Sources/PickleballKit/PickleballGame.swift PickleballKit/Sources/PickleballKit/PickleballMatch.swift PickleballKit/Tests/PickleballKitTests/MatchTestSupport.swift PickleballKit/Tests/PickleballKitTests/PickleballMatchInitialServiceTests.swift PickleballKit/Tests/PickleballKitTests/PickleballMatchTests.swift PickleballKit/Tests/PickleballKitTests/PickleballMatchCorrectScoresTests.swift PickleballKit/Tests/PickleballKitTests/PickleballMatchRehydrationTests.swift
# plus any other PickleballKit test file you had to change (list them explicitly in git add)
git commit -m "$(cat <<'EOF'
Initial service alternates every game (Rule 21.F.2)

The next game's first server is the opponent of the previous game's first
server, derived from the game's stored history (no schema change), instead of
the previous winner.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Announcer wording, Game Over prompt and sheet

**Files:**
- Modify: `ServerTwo/Voice/AnnouncementPlanner.swift`
- Modify: `ServerTwo/Scoring/ScoringPromptSheet.swift`
- Modify: `ServerTwo/Scoring/ScoringView.swift` (only the `.gameOver(` construction)
- Modify: `ServerTwoTests/AnnouncementPlannerTests.swift`
- Modify: `ServerTwoTests/ScoringPromptSheetTests.swift`

**Interfaces:**
- Consumes: Task 1's engine behavior (the snapshot of a live match after a game ends now has the OTHER team serving); `AnnouncementSnapshot.servingTeam`.
- Produces: planner wording; `ScoringPrompt.gameOver(... , firstServerName: String)` (new LAST associated value); `ScoringPromptSheet.firstServeLine(name:)` and `ScoringPromptSheet.switchSidesLine` (existing).

- [ ] **Step 1: Update the tests first (they fail until the code changes)**

In `ServerTwoTests/AnnouncementPlannerTests.swift` change these expectations (current text on the left):

- Side out, doubles forward (line ~81): `["Side out.", "2, 4, 1."]` → `["Side out.", "Fred serving.", "2, 4, 1."]`.
- Side out, singles forward (line ~88): `["Side out.", "2, 4."]` → `["Side out.", "Fred serving.", "2, 4."]`.
- Side out into game point (line ~196): `["Side out.", "10, 8, 1.", "Game point."]` → `["Side out.", "Delon serving.", "10, 8, 1.", "Game point."]` (the new serving team there is Team A).
- Side out to a team that is behind (line ~209): `["Side out.", "8, 10, 1."]` → `["Side out.", "Delon serving.", "8, 10, 1."]`.
- Game completed lines (each `"Next game, ..."` takes the NEW game's serving team from the `new` snapshot):
  - line ~271 (`testAGameCompletedWhileTheFlagWasTrueSpeaksNoSwitchLine`, new serving defaults to Team A): `"Next game, 0, 0, 2."` → `"Next game, Delon serving, 0, 0, 2."`.
  - line ~278 (`new` has `serving: .teamA`): → `"Next game, Delon serving, 0, 0, 2."`.
  - line ~285 (`new` has `serving: .teamB`, Fred): → `"Next game, Fred serving, 0, 0, 2."`.
  - line ~291 (no-engine-winner test, default Team A): → `"Next game, Delon serving, 0, 0, 2."`.
  - line ~300 (singles, `serving: .teamA`): `"Next game, 0, 0."` → `"Next game, Delon serving, 0, 0."`.
- `testSnapshotReflectsALiveMatchAcrossAGameBoundary` (live engine; after Team A wins game 1 the OTHER team serves game 2): add `XCTAssertEqual(after.servingTeam, .teamB)` next to the other `after` assertions and change the final expectation to `["Game 1 to Delon, 11 to 0.", "Switch sides.", "Next game, Fred serving, 0, 0, 2."]`.

Add these new tests inside the "Side out and second server" section:

```swift
    func testTheSideOutNamesTheNewServingTeamWhoeverItIs() {
        let toB = plan(snap(a: 4, b: 2, serving: .teamA, server: .two, moves: 5),
                       snap(a: 4, b: 2, serving: .teamB, server: .one, moves: 6))
        XCTAssertEqual(toB, ["Side out.", "Fred serving.", "2, 4, 1."])
        let toA = plan(snap(a: 4, b: 2, serving: .teamB, server: .two, moves: 5),
                       snap(a: 4, b: 2, serving: .teamA, server: .one, moves: 6))
        XCTAssertEqual(toA, ["Side out.", "Delon serving.", "4, 2, 1."])
    }

    func testTheServingTeamIsNotNamedOnASecondServerOrAPlainPoint() {
        XCTAssertEqual(plan(snap(a: 4, b: 2, serving: .teamA, server: .one, moves: 5),
                            snap(a: 4, b: 2, serving: .teamA, server: .two, moves: 6)), ["Second server.", "4, 2, 2."])
        XCTAssertEqual(plan(snap(a: 3, b: 2, serving: .teamA, server: .one, moves: 5),
                            snap(a: 4, b: 2, serving: .teamA, server: .one, moves: 6)), ["4, 2, 1."])
    }

    func testASideOutUndoDoesNotNameTheServingTeam() {
        let old = snap(a: 4, b: 2, serving: .teamB, server: .one, moves: 6)
        let new = snap(a: 4, b: 2, serving: .teamA, server: .two, moves: 5)
        XCTAssertEqual(plan(old, new), ["4, 2, 2."])
    }
```

In `ServerTwoTests/ScoringPromptSheetTests.swift`: both existing `ScoringPrompt.gameOver(` constructions (lines ~78 and ~128) gain a final argument `, firstServerName: "B"`, and add:

```swift
    func testFirstServeLineNamesTheNextGamesFirstServer() {
        XCTAssertEqual(ScoringPromptSheet.firstServeLine(name: "Fred"), "First serve: Fred.")
        XCTAssertEqual(ScoringPromptSheet.firstServeLine(name: "Delon & Katie"), "First serve: Delon & Katie.")
    }
```

Run `-only-testing:ServerTwoTests/AnnouncementPlannerTests -only-testing:ServerTwoTests/ScoringPromptSheetTests` (bundle `/tmp/svc2.xcresult`). Expected: compile error / failures (the new associated value and the new wording do not exist yet).

- [ ] **Step 2: Planner**

In `ServerTwo/Voice/AnnouncementPlanner.swift`:

1. In the non-final game-completed return, replace

```swift
                "Next game, \(scoreCall(new, configuration: configuration)).",
```

with

```swift
                "Next game, \(name(new.servingTeam)) serving, \(scoreCall(new, configuration: configuration)).",
```

(`new.servingTeam` is the freshly created game's first server: Rule 21.F.2 makes it the opponent of the game just finished, not the winner.)

2. In the referee-calls block replace

```swift
            if old.servingTeam != new.servingTeam {
                lines.append("Side out.")
            } else if configuration.playMode == .doubles, old.serverNumber == .one, new.serverNumber == .two {
```

with

```swift
            if old.servingTeam != new.servingTeam {
                // Say who has the serve now: "Side out." alone does not tell a
                // noisy court which team that is.
                lines.append("Side out.")
                lines.append("\(name(new.servingTeam)) serving.")
            } else if configuration.playMode == .doubles, old.serverNumber == .one, new.serverNumber == .two {
```

3. Update the doc comment at the top of the enum: slot 1 is `"Side out."` + `"<name> serving."` (two sentences) or `"Second server."`.

- [ ] **Step 3: Game Over prompt and sheet**

In `ServerTwo/Scoring/ScoringPromptSheet.swift`:

- The enum case becomes (new LAST associated value):

```swift
    case gameOver(
        gameNumber: Int,
        teamAName: String, teamBName: String,
        teamAScore: Int, teamBScore: Int,
        winner: Team?,
        teamAGames: Int, teamBGames: Int,
        firstServerName: String
    )
```

- In the rendering switch, replace `case let .gameOver(gameNumber, teamAName, teamBName, teamAScore, teamBScore, winner, teamAGames, teamBGames):` and its call with:

```swift
            case let .gameOver(gameNumber, teamAName, teamBName, teamAScore, teamBScore, winner, teamAGames, teamBGames, firstServerName):
                gameOver(
                    gameNumber: gameNumber, teamAName: teamAName, teamBName: teamBName,
                    teamAScore: teamAScore, teamBScore: teamBScore, winner: winner,
                    teamAGames: teamAGames, teamBGames: teamBGames,
                    firstServerName: firstServerName
                )
```

- Add `firstServerName: String` as the last parameter of `private func gameOver(...)`, and in its tally block insert the new line between the switch-sides line and "Next game starts at 0-0.":

```swift
                Text(Self.switchSidesLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(Self.firstServeLine(name: firstServerName))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Next game starts at 0-0.")
```

- Next to `switchSidesLine` add:

```swift
    /// Initial service changes every game (Rule 21.F.2), so the first server is
    /// no longer the previous winner and the sheet says who it is. "First
    /// serve: <name>." is grammatical for a singles name, a combined doubles
    /// name and the Team A/Team B fallback.
    static func firstServeLine(name: String) -> String {
        "First serve: \(name)."
    }
```

- The `#Preview("Game Over")` call gains `firstServerName: "Fred"`.
- The fixed Game Over detent (`case .gameOver: 420`): the extra line adds about 20 pt. Capture a temporary screenshot of the Game Over sheet (a UI test reaches it; use `xcrun simctl io 3C7D4B7A-F035-4AD7-89FF-B08256AF2516 screenshot /tmp/gameover.png` while it is up) and LOOK at it: nothing clipped, the dismiss button fully visible. If it clips, raise the detent by the smallest amount that fixes it. Remove temporary screenshot code before committing.

In `ServerTwo/Scoring/ScoringView.swift` only the `.gameOver(` construction (in the `completedGames.count` handler) changes: add a last argument

```swift
                    teamBGames: match.gamesWon(for: .teamB),
                    // `completedGames.last` is the game just finished; the match
                    // has already created the next game, so `currentGame` is its
                    // fresh game and its serving team is the next first server.
                    firstServerName: match.currentGame.state.servingTeam == .teamA
                        ? activeMatchController.teamAName
                        : activeMatchController.teamBName
```

- [ ] **Step 4: Run the focused tests**

Run the Step 1 command again. Expected: `Passed`, all tests in `AnnouncementPlannerTests` (49: the current 46 + 3 new) and `ScoringPromptSheetTests` (existing + 1 new) pass.

- [ ] **Step 5: Commit**

```bash
git add ServerTwo/Voice/AnnouncementPlanner.swift ServerTwo/Scoring/ScoringPromptSheet.swift ServerTwo/Scoring/ScoringView.swift ServerTwoTests/AnnouncementPlannerTests.swift ServerTwoTests/ScoringPromptSheetTests.swift
git commit -m "$(cat <<'EOF'
Say who serves: side-out and new-game callouts, Game Over first-serve line

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: App test updates, UI test, How to Play, full verification

**Files:**
- Modify: `ServerTwoTests/ActiveMatchControllerTests.swift` (helper + updates) and any other `ServerTwoTests` file that fails after Task 1
- Modify: `ServerTwoUITests/ScoringPromptsUITests.swift`
- Modify: `ServerTwo/HowToPlay/HowToPlayView.swift`
- Modify: `docs/superpowers/specs/2026-10-17-initial-service-alternation-design.md` (append "As built")

**Interfaces:**
- Consumes: Task 1's engine, Task 2's prompt line.
- Produces: the finished feature and a green full suite.

- [ ] **Step 1: Find the failing app unit tests**

Run only the unit target (bundle `/tmp/svc3-units.xcresult`): `-only-testing:ServerTwoTests`. Expected: failures in `ActiveMatchControllerTests` (about 14 loops of `for _ in 1...11 { controller.recordPoint(for: .teamA) }`, those that play a game after game 1, assuming Team A serves first again) and possibly others (`MatchDetailViewTests`, anything that builds a multi-game match through the engine). List every failing test.

- [ ] **Step 2: Add the controller helper and update the tests (intent preserved)**

Add to `ServerTwoTests/ActiveMatchControllerTests.swift` (file scope, below the imports):

```swift
/// Plays out one whole game for `winner` through the controller without
/// assuming who serves first (Rule 21.F.2: the first server alternates, so a
/// later game can start with the OTHER team serving and a winner who is
/// receiving must first win side-outs). Bounded so a bug fails instead of
/// hanging.
@MainActor
func playOutGame(
    _ controller: ActiveMatchController,
    winner: Team,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let target = (controller.match?.completedGames.count ?? 0) + 1
    var taps = 0
    while (controller.match?.completedGames.count ?? 0) < target, taps < 200 {
        controller.recordPoint(for: winner)
        taps += 1
    }
    XCTAssertEqual(controller.match?.completedGames.count, target, "the game never finished for \(winner)", file: file, line: line)
}
```

Update every failing test as in Task 1 Step 5: replace later-game `for _ in 1...11 { controller.recordPoint(for: .teamA) }` loops with `playOutGame(controller, winner: .teamA)`; keep game-1 loops; change `servingTeam` expectations that said the winner serves next (`ActiveMatchControllerTests` lines ~58 and ~95 are checks to read and adapt: keep what each verifies, update the expected team and name the rule in a comment); where an assertion depends on the number of taps (completion dates, undo/replay counts), preserve the assertion's intent and adjust numbers, explaining in a comment. Never delete or weaken an assertion; list every changed test with old and new behavior in the report.

- [ ] **Step 3: UI test and How to Play**

In `ServerTwoUITests/ScoringPromptsUITests.swift`, in `testGameOverAfterCorrectionThenCancelMatchPrompt`, directly after `XCTAssertTrue(app.staticTexts["Teams switch sides."].exists)` add:

```swift
        // The first server of game 2 is the OTHER team than game 1's first
        // server (Rule 21.F.2), whichever team the coin flip picked.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'First serve:'")).firstMatch.exists,
            "the Game Over sheet names who serves first"
        )
```

In `ServerTwo/HowToPlay/HowToPlayView.swift` (the doubles scoring paragraph, `Text("In doubles, the score is called as three numbers ...`), replace the final sentence `Server Two tracks all of this automatically.` with `After every game the teams switch sides and the other team serves first (Rule 21.F.2). Server Two tracks all of this automatically.` (keep the rest of the string exactly).

- [ ] **Step 4: Run the full suite once and check for warnings**

Run the full suite once (bundle `/tmp/svc3-full.xcresult`, log `/tmp/svc3-full.log`); expected: `Passed`, 0 failed (previous full run: 177; this plan adds 3 planner tests and 1 sheet test in the app target, so about 181; report the exact total). Also run PickleballKit once more from `PickleballKit/` (expect 173). Confirm the log really compiled the edited app files (`grep -c "SwiftCompile.*HowToPlayView.swift" /tmp/svc3-full.log` is at least 1; otherwise touch the edited Swift files and rebuild with `xcodebuild build-for-testing` into a separate log), then run `grep -E "warning:" <that log> | grep -E "ServerTwo/Voice/|ServerTwo/Scoring/|ServerTwo/HowToPlay/|ActiveMatchControllerTests.swift|AnnouncementPlannerTests.swift|ScoringPromptSheetTests.swift|ScoringPromptsUITests.swift"`: must be empty (report the command, the SwiftCompile count and the output).

- [ ] **Step 5: Append "As built" to the spec and commit**

Append to `docs/superpowers/specs/2026-10-17-initial-service-alternation-design.md`:

```markdown

## As built

- `PickleballGame.initialServingTeam` (`history.first?.servingTeam ?? state.servingTeam`) is derived, with no stored field or Codable change. Both next-game creation sites in `PickleballMatch` use `currentGame.initialServingTeam.opponent` (Rule 21.F.2); the first server alternates every game and no longer depends on who won.
- The announcer says "Side out." followed by "<new serving team> serving." on a forward side-out in side-out scoring, and "Next game, <first server> serving, <call>." when a game ends; "Second server." has no team name. The Game Over sheet shows "First serve: <name>." between "Teams switch sides." and "Next game starts at 0-0."; the prompt's `firstServerName` is read from `match.currentGame.state.servingTeam` (already the new game).
- Existing multi-game tests were updated through `playOutGame` helpers (PickleballKit test target and `ActiveMatchControllerTests`); each kept its intent.
- Not changed: `undo()` Branch 3's documented limitation; Rule 21.F.3 (starting server within a team).
- Device checks owed: best of 3: after game 1 the Game Over sheet says the OTHER team than game 1's first server serves first, whoever won, and the spoken line names it ("Next game, <name> serving, 0, 0, 2."); game 3 starts with game 1's first server; "Side out. <name> serving. ..." names the new serving team and is not spoken after undo; "Second server." has no name.
```

```bash
git add ServerTwoTests/ActiveMatchControllerTests.swift ServerTwoUITests/ScoringPromptsUITests.swift ServerTwo/HowToPlay/HowToPlayView.swift docs/superpowers/specs/2026-10-17-initial-service-alternation-design.md
# plus any other ServerTwoTests file you had to change (list them explicitly in git add)
git commit -m "$(cat <<'EOF'
Update multi-game app tests for alternating initial service; How to Play note

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Final report to the controller**

State the full-suite and PickleballKit totals, the warning-grep command, SwiftCompile count and output, the list of every test you changed (file, old behavior, new behavior), any Game Over detent change, and the device checks from "As built" as NOT verified.
