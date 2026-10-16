# Atomic Two-Score Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user correct a live game's score by setting BOTH teams' scores in one step, gated so a correction can never end the game mid-edit or leave a game that can never end by scoring — plus the engine/undo hardening, a data-loss fallback, and small Quick Log cleanups that the review of this work surfaced.

**Architecture:** A pure `GameConfiguration.isReachableGameScore` rule gates the UI. A new atomic `correctScores(teamA:teamB:)` on `PickleballGame` and `PickleballMatch` sets both scores and evaluates game-over ONCE; the match's win/loss bookkeeping is extracted into a shared `reconcileCurrentGame` helper that `correctScores` and `undo()` both use. `ScoreCorrectionSheet` becomes a two-stepper sheet whose Save is gated by the rule.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest/XCUITest. `PickleballKit` (local Swift package) holds the engine; `ServerTwo` is the app target.

**Spec:** `docs/superpowers/specs/2026-10-16-score-correction-design.md`

## Global Constraints

- The engine does NOT validate reachability: `correctScores` sets what it's given (same as `correctScore` today). The UI gates via `isReachableGameScore`.
- `PickleballGame.correctScore(team:to:)` and `PickleballMatch.correctScore(team:to:)` stay as thin wrappers over the atomic methods, with identical behavior — every existing test for them must pass UNCHANGED. They are NOT marked `@available(deprecated)` (that would add warnings to every test build; test output must stay pristine).
- `ActiveMatchController.correctScore(team:to:)` is REMOVED (in Task 5, once `ScoringView` stops calling it, so every commit builds); its two test call sites migrate to `correctScores(teamA:teamB:)` (Task 4).
- `PickleballMatch.undo()` Branch 3 (pop the previous completed game) and the old-snapshot impossible-score case in `undo()` are NOT changed.
- `correctScores` forces `lastPointWonWhileServing = true` (existing, tested behavior), so under `.rally(freeze: true)` a correction to a completed-by-score pair ends the game; an in-progress frozen state at/above the target can't be entered through correction. Accepted.
- Only the CURRENT game is correctable (earlier archived games are not).
- `PickleballKit` tests run from inside `PickleballKit/` with `swift test` (currently 128 XCTest tests, all passing; the "Swift Testing … 0 tests" line is irrelevant — read the `Executed N tests` lines).
- App-target tests run ONLY on the iOS 27 simulator BY ID, serially: `xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath <path>`. NEVER use `name=iPhone 17 Pro` (ambiguous with an iOS 26.5 simulator that can't run this target) and never raise concurrency above 2. `rm -rf` the result bundle path before reuse. Current app suite: 53/53 passing.
- Verify app-test results ONLY with `xcrun xcresulttool get test-results summary --path <bundle>` (and `get test-results tests` for failure detail). SourceKit "No such module" diagnostics are false positives here.
- `xcodebuild` can hang 10+ minutes after a failing run or on a UI "wait for idle"; if so `pkill -f xcodebuild`, then rerun once. A freshly booted simulator can fail with "Timed out while loading Accessibility" — just rerun. There is no `timeout` command on macOS.
- Token awareness: exactly ONE new UI test; all logic is covered by fast `PickleballKit`/`ServerTwoTests` unit tests. Batch simulator runs.
- Stage specific files only. NEVER stage `ServerTwo.xcodeproj/xcuserdata/delonsampaio.xcuserdatad/xcschemes/xcschememanagement.plist` (unrelated Xcode state that is always modified in this working tree).
- Commit messages end with the line: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`

## Review Focus

- Undo after an atomic correction, in every branch: correction that completes a non-final game of a best-of-3 (Branch 3), completes the final game (Branch 1), stays in-progress (Branch 2), and — engine-only, UI-unreachable but a real invariant — un-counts or flips a decided game, or leaves its winner unchanged (these three FAIL against today's `undo()` and are the proof the reconcile fix is needed). (Task 2)
- Correcting up to the target while only one point ahead (opponent one point from the target): 9-10 → 11-10 must stay in progress (margin 1), not end the game. (Task 2: `testCorrectingToTheTargetWhileOnlyOnePointAheadStaysInProgress`)
- A correction that crosses the side-switch threshold AND ends the match (5-5 → 11-9 best-of-1): the engine leaves `hasSideSwitched` true on the finished game, which is why the view must not show the "Side Switch" alert when `match.isMatchOver`. (Task 2 characterization + Task 5 view guard)
- Recovering from an already-stuck game: if the CURRENT pair is unreachable (e.g. a legacy 12-9), Save stays disabled until the user fixes the pair, and a fixed pair becomes saveable; an unchanged stuck pair is not saveable. (Task 5 `ScoreCorrectionSheetTests`)
- Reachability under win-by-2 OFF and `.rally(freeze: true)`, and for 15/21-point targets: `12-10` and `11-11` unreachable with win-by-2 off; every non-negative pair reachable under freeze. (Task 1)

---

### Task 1: `isReachableGameScore` and atomic `PickleballGame.correctScores`

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/GameConfiguration.swift`
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift` (`correctScore`, currently ~lines 159-168)
- Create: `PickleballKit/Tests/PickleballKitTests/GameConfigurationReachableScoreTests.swift`
- Create: `PickleballKit/Tests/PickleballKitTests/PickleballGameCorrectScoresTests.swift`

**Interfaces:**
- Produces: `GameConfiguration.isReachableGameScore(teamA: Int, teamB: Int) -> Bool` (public); `PickleballGame.correctScores(teamA: Int, teamB: Int)` (public) — consumed by Task 2, Task 4 and Task 5.
- Consumes: `GameConfiguration.isCompletedGameScore(teamA:teamB:)` (existing).

- [ ] **Step 1: Write the failing reachability tests**

Create `PickleballKit/Tests/PickleballKitTests/GameConfigurationReachableScoreTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class GameConfigurationReachableScoreTests: XCTestCase {
    private let elevenWinByTwo = GameConfiguration(winningScore: .eleven, winByTwo: true)

    func testNegativeScoresAreUnreachable() {
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: -1, teamB: 5))
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 5, teamB: -1))
    }

    func testAnyScoreBelowTheTargetIsReachable() {
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 0, teamB: 0))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 3, teamB: 0))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 10, teamB: 10))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 10, teamB: 9))
    }

    func testCompletedFinalsAreReachable() {
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 9))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 0))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 12, teamB: 10))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 13, teamB: 11))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 9, teamB: 11))
    }

    func testInProgressScoresAtOrAboveTheTargetAreReachableWhenTiedOrOneAhead() {
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 10))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 11))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 12, teamB: 11))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 12, teamB: 12))
        XCTAssertTrue(elevenWinByTwo.isReachableGameScore(teamA: 11, teamB: 12))
    }

    func testOvershotScoresWithAMarginOfThreeOrMoreAreUnreachable() {
        // 12-9 / 13-10 / 15-3: the game would already have ended earlier, and
        // more points can never produce an exact 2-point overtime margin.
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 12, teamB: 9))
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 9, teamB: 12))
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 13, teamB: 10))
        XCTAssertFalse(elevenWinByTwo.isReachableGameScore(teamA: 15, teamB: 3))
    }

    func testWinByTwoOffOnlyAllowsAnExactTargetFinalOrBelow() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: false)
        XCTAssertTrue(config.isReachableGameScore(teamA: 11, teamB: 10))   // completed: first to 11
        XCTAssertTrue(config.isReachableGameScore(teamA: 11, teamB: 0))
        XCTAssertTrue(config.isReachableGameScore(teamA: 10, teamB: 10))   // below target
        XCTAssertFalse(config.isReachableGameScore(teamA: 12, teamB: 10))  // would have ended at 11-10
        XCTAssertFalse(config.isReachableGameScore(teamA: 11, teamB: 11))  // would have ended at 11-10
        XCTAssertFalse(config.isReachableGameScore(teamA: 12, teamB: 12))
    }

    func testFreezeIsPermissiveForEveryNonNegativePair() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: true), winningScore: .eleven, winByTwo: true)
        XCTAssertTrue(config.isReachableGameScore(teamA: 20, teamB: 3))
        XCTAssertTrue(config.isReachableGameScore(teamA: 12, teamB: 9))
        XCTAssertTrue(config.isReachableGameScore(teamA: 0, teamB: 0))
        XCTAssertFalse(config.isReachableGameScore(teamA: -1, teamB: 0))
    }

    func testRallyWithoutFreezeUsesTheSameRulesAsSideOut() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)
        XCTAssertFalse(config.isReachableGameScore(teamA: 12, teamB: 9))
        XCTAssertTrue(config.isReachableGameScore(teamA: 12, teamB: 11))
    }

    func testFifteenAndTwentyOnePointTargets() {
        let fifteen = GameConfiguration(winningScore: .fifteen, winByTwo: true)
        XCTAssertTrue(fifteen.isReachableGameScore(teamA: 15, teamB: 13))
        XCTAssertTrue(fifteen.isReachableGameScore(teamA: 15, teamB: 14))   // in progress
        XCTAssertTrue(fifteen.isReachableGameScore(teamA: 14, teamB: 14))
        XCTAssertFalse(fifteen.isReachableGameScore(teamA: 16, teamB: 13))

        let twentyOne = GameConfiguration(winningScore: .twentyOne, winByTwo: true)
        XCTAssertTrue(twentyOne.isReachableGameScore(teamA: 21, teamB: 19))
        XCTAssertTrue(twentyOne.isReachableGameScore(teamA: 20, teamB: 20))
        XCTAssertTrue(twentyOne.isReachableGameScore(teamA: 21, teamB: 20))
        XCTAssertFalse(twentyOne.isReachableGameScore(teamA: 22, teamB: 19))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run (from inside `PickleballKit/`): `swift test --filter GameConfigurationReachableScoreTests 2>&1 | grep -E "Executed|error:" | head`
Expected: build FAILS with "value of type 'GameConfiguration' has no member 'isReachableGameScore'".

- [ ] **Step 3: Implement `isReachableGameScore`**

In `PickleballKit/Sources/PickleballKit/GameConfiguration.swift`, add this method inside `GameConfiguration`, right after `isCompletedGameScore` (before the struct's closing `}`):

```swift
    /// Whether `teamA`/`teamB` is a score live play could actually produce:
    /// a legal completed final (see `isCompletedGameScore`) or a legal
    /// in-progress score. Used to gate manual score correction, so a
    /// correction can never leave a game that ends mid-edit or can never end
    /// by scoring more points.
    ///
    /// `.rally(freeze: true)` is deliberately permissive for scores above the
    /// target — same stance as `isCompletedGameScore`, since freeze's margin
    /// depends on serve-sequence state this pure check can't see.
    public func isReachableGameScore(teamA: Int, teamB: Int) -> Bool {
        guard teamA >= 0, teamB >= 0 else { return false }
        if isCompletedGameScore(teamA: teamA, teamB: teamB) { return true }
        if max(teamA, teamB) < winningScore.rawValue { return true }
        if case .rally(let freeze) = scoringFormat, freeze { return true }
        // At/above the target in a non-freeze game, play only continues when
        // win-by-2 is on and the score is tied or one ahead.
        return winByTwo && abs(teamA - teamB) <= 1
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter GameConfigurationReachableScoreTests 2>&1 | grep -E "Executed|error:" | head`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 5: Write the failing `PickleballGame.correctScores` tests**

Create `PickleballKit/Tests/PickleballKitTests/PickleballGameCorrectScoresTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballGameCorrectScoresTests: XCTestCase {
    private func makeGame(_ configuration: GameConfiguration = GameConfiguration(winningScore: .eleven, winByTwo: true)) -> PickleballGame {
        PickleballGame(configuration: configuration, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    }

    func testCorrectScoresSetsBothScores() {
        let game = makeGame()
        game.correctScores(teamA: 7, teamB: 4)
        XCTAssertEqual(game.state.teamAScore, 7)
        XCTAssertEqual(game.state.teamBScore, 4)
    }

    func testCorrectScoresIsASingleUndoStep() {
        let game = makeGame()
        game.correctScores(teamA: 7, teamB: 4)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
        XCTAssertFalse(game.canUndo, "one correction must add exactly one history entry")
    }

    func testCorrectScoresClampsNegativeValuesToZero() {
        let game = makeGame()
        game.correctScores(teamA: -3, teamB: 5)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 5)
    }

    func testCorrectScoresTriggersTheSideSwitchWhenEitherTeamCrossesTheThreshold() {
        // Threshold for an 11-point game is 6.
        let viaTeamB = makeGame()
        viaTeamB.correctScores(teamA: 2, teamB: 6)
        XCTAssertTrue(viaTeamB.state.hasSideSwitched)

        let viaTeamA = makeGame()
        viaTeamA.correctScores(teamA: 6, teamB: 2)
        XCTAssertTrue(viaTeamA.state.hasSideSwitched)

        let neither = makeGame()
        neither.correctScores(teamA: 5, teamB: 5)
        XCTAssertFalse(neither.state.hasSideSwitched)
    }

    func testCorrectScoresDoesNotValidateReachability() {
        // The engine trusts its caller (the UI gates via isReachableGameScore):
        // an unreachable pair is set as given, and is simply not a completed game.
        let game = makeGame()
        game.correctScores(teamA: 12, teamB: 9)
        XCTAssertEqual(game.state.teamAScore, 12)
        XCTAssertEqual(game.state.teamBScore, 9)
        XCTAssertNil(game.gameWinner)
    }

    func testCorrectScoresForcesLastPointWonWhileServingSoAFrozenGameCanEnd() {
        // Same setup as the existing single-team freeze test: reach a frozen 11-9.
        let config = GameConfiguration(scoringFormat: .rally(freeze: true), winningScore: .eleven, winByTwo: true)
        let game = makeGame(config)
        for _ in 1...10 { game.recordPoint(for: .teamA) }
        for _ in 1...9 { game.recordPoint(for: .teamB) }
        game.recordPoint(for: .teamA)
        XCTAssertEqual(game.state.teamAScore, 11)
        XCTAssertEqual(game.state.teamBScore, 9)
        XCTAssertFalse(game.isGameOver, "frozen: the winning point was won on receive")

        game.correctScores(teamA: 11, teamB: 9)

        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }

    func testSingleTeamCorrectScoreKeepsTheOtherTeamsScoreAndIsOneUndoStep() {
        let game = makeGame()
        game.correctScores(teamA: 5, teamB: 3)
        game.correctScore(team: .teamA, to: 8)
        XCTAssertEqual(game.state.teamAScore, 8)
        XCTAssertEqual(game.state.teamBScore, 3)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 5)
        XCTAssertEqual(game.state.teamBScore, 3)
    }
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `swift test --filter PickleballGameCorrectScoresTests 2>&1 | grep -E "Executed|error:" | head`
Expected: build FAILS with "value of type 'PickleballGame' has no member 'correctScores'".

- [ ] **Step 7: Implement `correctScores` and reimplement `correctScore` over it**

In `PickleballKit/Sources/PickleballKit/PickleballGame.swift`, replace:

```swift
    public func correctScore(team: Team, to newScore: Int) {
        history.append(state)
        if team == .teamA {
            state.teamAScore = max(0, newScore)
        } else {
            state.teamBScore = max(0, newScore)
        }
        checkSideSwitch()
        state.lastPointWonWhileServing = true
    }
```

with:

```swift
    /// Sets BOTH teams' scores in one step — one undo-history entry, one
    /// side-switch check — so a two-team correction never passes through an
    /// intermediate board the engine would act on. Does not validate that
    /// the pair is reachable (the UI gates that via
    /// `GameConfiguration.isReachableGameScore`).
    public func correctScores(teamA: Int, teamB: Int) {
        history.append(state)
        state.teamAScore = max(0, teamA)
        state.teamBScore = max(0, teamB)
        checkSideSwitch()
        state.lastPointWonWhileServing = true
    }

    public func correctScore(team: Team, to newScore: Int) {
        correctScores(
            teamA: team == .teamA ? newScore : state.teamAScore,
            teamB: team == .teamB ? newScore : state.teamBScore
        )
    }
```

- [ ] **Step 8: Run the full PickleballKit suite**

Run: `swift test 2>&1 | grep -E "Executed|error:|failed" | tail -3`
Expected: `Executed 144 tests, with 0 failures` (128 existing + 9 reachability + 7 correctScores). Every pre-existing test, including `PickleballGameUndoAndCorrectionTests`, passes unchanged.

- [ ] **Step 9: Commit**

```bash
cd "/Users/delonsampaio/Desktop/VSCode Workspaces/ServerTwo"
git add PickleballKit/Sources/PickleballKit/GameConfiguration.swift PickleballKit/Sources/PickleballKit/PickleballGame.swift PickleballKit/Tests/PickleballKitTests/GameConfigurationReachableScoreTests.swift PickleballKit/Tests/PickleballKitTests/PickleballGameCorrectScoresTests.swift
git commit -m "$(cat <<'EOF'
Add isReachableGameScore and atomic PickleballGame.correctScores

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Atomic `PickleballMatch.correctScores` and undo reconciliation

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballMatch.swift` (`undo()` ~lines 92-117, `correctScore` ~lines 119-150)
- Create: `PickleballKit/Tests/PickleballKitTests/PickleballMatchCorrectScoresTests.swift`

**Interfaces:**
- Consumes: `PickleballGame.correctScores(teamA:teamB:)` from Task 1.
- Produces: `PickleballMatch.correctScores(teamA: Int, teamB: Int)` (public) — consumed by Task 4; a private `reconcileCurrentGame(wasCounted:previousWinner:)`.

This task is a refactor plus a bug fix, so it runs: refactor (suite stays green) → write tests → three FAIL against today's `undo()` → fix `undo()` → all pass.

- [ ] **Step 1: Extract the reconcile helper and add `correctScores` (leave `undo()` untouched)**

In `PickleballKit/Sources/PickleballKit/PickleballMatch.swift`, replace the whole existing `correctScore(team:to:)`:

```swift
    public func correctScore(team: Team, to newScore: Int) {
        let wasCounted = currentGameIsCounted
        let previousWinner = wasCounted ? currentGame.gameWinner : nil

        currentGame.correctScore(team: team, to: newScore)

        let newWinner = currentGame.gameWinner

        guard previousWinner != newWinner else { return }

        if let previousWinner {
            gamesWon[previousWinner, default: 0] -= 1
            if wasCounted {
                completedGames.removeLast()
                currentGameIsCounted = false
            }
        }

        if let newWinner {
            gamesWon[newWinner, default: 0] += 1
            completedGames.append(currentGame)
            currentGameIsCounted = true
            if !isMatchOver {
                currentGame = PickleballGame(
                    configuration: configuration,
                    firstServingTeam: newWinner,
                    proUnlocked: currentGame.proUnlocked,
                    demoPointCap: currentGame.demoPointCap
                )
                currentGameIsCounted = false
            }
        }
    }
```

with:

```swift
    /// Sets BOTH scores of the current game in one step and evaluates the
    /// win/loss bookkeeping ONCE afterwards (see `reconcileCurrentGame`), so a
    /// two-team correction never ends — or archives — a game on an
    /// intermediate board. One undo restores both scores and the bookkeeping.
    public func correctScores(teamA: Int, teamB: Int) {
        let wasCounted = currentGameIsCounted
        let previousWinner = wasCounted ? currentGame.gameWinner : nil

        currentGame.correctScores(teamA: teamA, teamB: teamB)

        reconcileCurrentGame(wasCounted: wasCounted, previousWinner: previousWinner)
    }

    public func correctScore(team: Team, to newScore: Int) {
        correctScores(
            teamA: team == .teamA ? newScore : currentGame.state.teamAScore,
            teamB: team == .teamB ? newScore : currentGame.state.teamBScore
        )
    }

    /// Brings `gamesWon`/`completedGames`/`currentGame` back in line with
    /// `currentGame.gameWinner` after the current game's score changed
    /// through a correction or an undo. `previousWinner` is the winner the
    /// match had ALREADY counted for `currentGame` before the change (nil when
    /// `currentGame` wasn't counted).
    private func reconcileCurrentGame(wasCounted: Bool, previousWinner: Team?) {
        let newWinner = currentGame.gameWinner

        guard previousWinner != newWinner else { return }

        if let previousWinner {
            gamesWon[previousWinner, default: 0] -= 1
            if wasCounted {
                completedGames.removeLast()
                currentGameIsCounted = false
            }
        }

        if let newWinner {
            gamesWon[newWinner, default: 0] += 1
            completedGames.append(currentGame)
            currentGameIsCounted = true
            if !isMatchOver {
                currentGame = PickleballGame(
                    configuration: configuration,
                    firstServingTeam: newWinner,
                    proUnlocked: currentGame.proUnlocked,
                    demoPointCap: currentGame.demoPointCap
                )
                currentGameIsCounted = false
            }
        }
    }
```

- [ ] **Step 2: Run the existing suite to confirm the refactor is behavior-preserving**

Run (from `PickleballKit/`): `swift test 2>&1 | grep -E "Executed|error:|failed" | tail -3`
Expected: `Executed 144 tests, with 0 failures` — all pre-existing `correctScore`/undo tests (`PickleballMatchTests`, `PickleballGameUndoAndCorrectionTests`, rehydration/snapshot tests) pass unchanged.

- [ ] **Step 3: Write the tests (hand-traced against the engine)**

Create `PickleballKit/Tests/PickleballKitTests/PickleballMatchCorrectScoresTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballMatchCorrectScoresTests: XCTestCase {
    private let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

    private func makeMatch(_ format: MatchFormat) -> PickleballMatch {
        PickleballMatch(configuration: config, matchFormat: format, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    }

    // MARK: - UI-reachable paths

    func testTwoTeamCorrectionThroughAnIntermediateScoreNeverEndsTheGame() {
        // 9-9 -> 12-11 in one step. Done as two single-team edits, the first
        // write (12-9) was the problem; the atomic call evaluates only 12-11.
        let match = makeMatch(.bestOfOne)
        match.correctScores(teamA: 9, teamB: 9)
        match.correctScores(teamA: 12, teamB: 11)

        XCTAssertEqual(match.currentGame.state.teamAScore, 12)
        XCTAssertEqual(match.currentGame.state.teamBScore, 11)
        XCTAssertFalse(match.isMatchOver)
        XCTAssertTrue(match.completedGames.isEmpty)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)

        match.undo()   // one undo restores BOTH scores
        XCTAssertEqual(match.currentGame.state.teamAScore, 9)
        XCTAssertEqual(match.currentGame.state.teamBScore, 9)
        match.undo()
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
    }

    func testCorrectingToTheTargetWhileOnlyOnePointAheadStaysInProgress() {
        // The opponent is one point from the target (10); the corrected pair
        // reaches the target but leads by only one, so win-by-2 keeps it live.
        let match = makeMatch(.bestOfOne)
        match.correctScores(teamA: 9, teamB: 10)
        match.correctScores(teamA: 11, teamB: 10)

        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertEqual(match.currentGame.state.teamAScore, 11)
        XCTAssertEqual(match.currentGame.state.teamBScore, 10)
    }

    func testCorrectionThatCompletesANonFinalGameArchivesItAndOneUndoRestoresEverything() {
        let match = makeMatch(.bestOfThree)
        match.correctScores(teamA: 11, teamB: 9)

        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertEqual(match.completedGames[0].state.teamAScore, 11)
        XCTAssertEqual(match.completedGames[0].state.teamBScore, 9)
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)   // fresh game 2
        XCTAssertEqual(match.currentGame.state.servingTeam, .teamA)
        XCTAssertFalse(match.isMatchOver)

        match.undo()   // Branch 3: pops the archived game and undoes the correction

        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertTrue(match.completedGames.isEmpty)
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertFalse(match.currentGameIsCounted)
    }

    func testCorrectionThatCompletesTheFinalGameEndsTheMatchAndOneUndoRestoresEverything() {
        let match = makeMatch(.bestOfThree)
        for _ in 1...11 { match.recordPoint(for: .teamA) }   // game 1: A wins 11-0
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)

        match.correctScores(teamA: 11, teamB: 9)              // game 2: A wins -> match over

        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon(for: .teamA), 2)
        XCTAssertEqual(match.completedGames.count, 2)
        XCTAssertTrue(match.currentGameIsCounted)

        match.undo()   // Branch 1

        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertFalse(match.currentGameIsCounted)
    }

    func testUndoingTheMatchDecidingPointStillUncountsTheGame() {
        // Guards the undo() refactor: normal play must be unchanged.
        let match = makeMatch(.bestOfOne)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        XCTAssertTrue(match.isMatchOver)

        match.undo()

        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertTrue(match.completedGames.isEmpty)
        XCTAssertEqual(match.currentGame.state.teamAScore, 10)
        XCTAssertFalse(match.currentGameIsCounted)
    }

    func testCorrectionThatCrossesTheSideSwitchThresholdAndEndsTheMatchLeavesBothFlagsSet() {
        // 0-0 -> 11-9 in a best-of-1: the game ends AND `hasSideSwitched`
        // flips on the finished game. The engine reports both; ScoringView
        // must not show "Side Switch" when `match.isMatchOver` (Task 5).
        let match = makeMatch(.bestOfOne)
        match.correctScores(teamA: 11, teamB: 9)

        XCTAssertTrue(match.isMatchOver)
        XCTAssertTrue(match.currentGame.state.hasSideSwitched)
    }

    // MARK: - Engine-only paths (UI-unreachable, but real invariants)
    // The next three FAIL against the pre-fix undo() — see Step 4.

    func testUndoingACorrectionThatUncountedADecidedGameRecountsIt() {
        let match = makeMatch(.bestOfOne)
        for _ in 1...11 { match.recordPoint(for: .teamA) }   // 11-0, counted
        match.correctScores(teamA: 10, teamB: 10)            // un-counts
        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)

        match.undo()                                          // back to 11-0

        XCTAssertEqual(match.currentGame.state.teamAScore, 11)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertTrue(match.currentGameIsCounted)
    }

    func testUndoingACorrectionThatFlippedTheWinnerRestoresTheOriginalWinner() {
        let match = makeMatch(.bestOfOne)
        for _ in 1...11 { match.recordPoint(for: .teamA) }   // 11-0, A wins
        match.correctScores(teamA: 9, teamB: 11)             // flips: B wins
        XCTAssertEqual(match.matchWinner, .teamB)
        XCTAssertEqual(match.gamesWon(for: .teamA), 0)
        XCTAssertEqual(match.gamesWon(for: .teamB), 1)

        match.undo()                                          // back to 11-0

        XCTAssertEqual(match.currentGame.state.teamAScore, 11)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.gamesWon(for: .teamB), 0)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertTrue(match.currentGameIsCounted)
    }

    func testUndoingACorrectionThatLeftTheWinnerUnchangedKeepsTheGameCounted() {
        let match = makeMatch(.bestOfOne)
        for _ in 1...11 { match.recordPoint(for: .teamA) }   // 11-0, A wins
        match.correctScores(teamA: 11, teamB: 7)             // still A wins
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)

        match.undo()                                          // back to 11-0

        XCTAssertEqual(match.currentGame.state.teamAScore, 11)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.gamesWon(for: .teamA), 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertTrue(match.currentGameIsCounted)
    }
}
```

Trace notes for the engine-only tests (so a reviewer can re-derive them): after `recordPoint` ×11 in best-of-1 the game is 11-0, counted, `gamesWon[A] == 1`, `completedGames.count == 1`. `correctScores(10, 10)`: `wasCounted = true`, `previousWinner = A`; `isCompletedGameScore(10,10)` is false (tied) → `newWinner == nil` → `gamesWon[A] = 0`, `completedGames` emptied, counted false. `correctScores(9, 11)`: `isCompletedGameScore(9,11)` is true (winner 11, margin 2, not overtime) → `newWinner = B` → A decremented, game removed, then B incremented and the game re-appended (match over, so no new game). `correctScores(11, 7)`: completed with winner A, equal to `previousWinner` → early return, nothing changes.

- [ ] **Step 4: Run to verify the three engine-only undo tests FAIL (RED) and the rest pass**

Run: `swift test --filter PickleballMatchCorrectScoresTests 2>&1 | grep -E "error:|Executed" | head -20`
Expected: the six UI-reachable/characterization tests PASS; `testUndoingACorrectionThatUncountedADecidedGameRecountsIt`, `testUndoingACorrectionThatFlippedTheWinnerRestoresTheOriginalWinner` and `testUndoingACorrectionThatLeftTheWinnerUnchangedKeepsTheGameCounted` FAIL (today's `undo()` leaves `gamesWon`/`completedGames` out of sync: e.g. un-count undo leaves `gamesWon(for: .teamA) == 0` while the score is back to 11-0). Record that these three failed before the fix in your report.

- [ ] **Step 5: Fix `undo()` Branches 1 and 2 to reconcile**

In `PickleballKit/Sources/PickleballKit/PickleballMatch.swift`, replace:

```swift
    public func undo() {
        if currentGameIsCounted {
            // The match ended on this exact game. Undoing the match-deciding
            // point must also reverse the win count, not just revert the
            // score.
            completedGames.removeLast()
            if let winner = currentGame.gameWinner {
                gamesWon[winner, default: 0] -= 1
            }
            currentGame.undo()
            currentGameIsCounted = false
            return
        }
        if currentGame.canUndo {
            currentGame.undo()
            return
        }
```

with:

```swift
    public func undo() {
        if currentGameIsCounted {
            // The match ended on this exact game. Undoing the match-deciding
            // point must also reverse the win count, not just revert the
            // score. Reconciling (rather than assuming the undone action was
            // the winning point) also handles undoing a CORRECTION that left
            // this game decided — same winner or a flipped one.
            let previousWinner = currentGame.gameWinner
            currentGame.undo()
            reconcileCurrentGame(wasCounted: true, previousWinner: previousWinner)
            return
        }
        if currentGame.canUndo {
            currentGame.undo()
            // Undoing a correction that un-counted a decided game restores a
            // decided score; reconcile re-counts it. For ordinary points this
            // is a no-op (an in-progress game stays in progress).
            reconcileCurrentGame(wasCounted: false, previousWinner: nil)
            return
        }
```

Leave the rest of `undo()` (the `guard let previousGame = completedGames.popLast()` Branch 3) exactly as it is.

- [ ] **Step 6: Run the new tests and the full suite**

Run: `swift test --filter PickleballMatchCorrectScoresTests 2>&1 | grep -E "error:|Executed" | tail -3` → expect `Executed 9 tests, with 0 failures`.
Run: `swift test 2>&1 | grep -E "Executed|error:|failed" | tail -3` → expect `Executed 153 tests, with 0 failures` (144 + 9). All existing undo/correction/rehydration tests pass unchanged.

- [ ] **Step 7: Commit**

```bash
git add PickleballKit/Sources/PickleballKit/PickleballMatch.swift PickleballKit/Tests/PickleballKitTests/PickleballMatchCorrectScoresTests.swift
git commit -m "$(cat <<'EOF'
Add atomic PickleballMatch.correctScores; reconcile winner bookkeeping in undo

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Persistence fallback and Quick Log repository test gaps

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift` (`saveCompletedMatch`, the `guard let gameWinner = game.gameWinner else { continue }` line, ~line 123)
- Modify: `PickleballKit/Tests/PickleballKitTests/MatchRepositoryHistoryTests.swift`
- Modify: `PickleballKit/Tests/PickleballKitTests/MatchRepositoryQuickLogTests.swift`

**Interfaces:** consumes nothing new; produces no new API.

- [ ] **Step 1: Write the failing fallback test**

Add to `MatchRepositoryHistoryTests` (inside the class, e.g. after `testSaveCompletedMatchThrowsIfMatchIsNotOver`):

```swift
    func testSaveCompletedMatchKeepsAGameWhoseScoreNoLongerCountsAsCompleted() throws {
        // A match restored from an in-progress snapshot saved BEFORE the strict
        // completed-score rule can hold a decided game at a score the rule no
        // longer recognises (12-9 with win-by-2: only reachable via an old
        // lenient correction). That game must be saved with the higher score
        // as its winner, not silently dropped.
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let finalState = GameState(
            teamAScore: 12, teamBScore: 9,
            servingTeam: .teamA, serverNumber: .one,
            teamATimeoutsRemaining: 2, teamBTimeoutsRemaining: 2,
            hasSideSwitched: true, lastPointWonWhileServing: true
        )
        func makeLegacyGame() -> PickleballGame {
            PickleballGame(configuration: config, state: finalState, history: [], proUnlocked: true, demoPointCap: nil)
        }
        XCTAssertNil(makeLegacyGame().gameWinner, "sanity: 12-9 is not a completed score under the strict rule")

        let match = PickleballMatch(
            configuration: config,
            matchFormat: .bestOfOne,
            completedGames: [makeLegacyGame()],
            currentGame: makeLegacyGame(),
            gamesWon: [.teamA: 1, .teamB: 0],
            currentGameIsCounted: true
        )

        let saved = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())

        XCTAssertEqual(saved.winningTeam, .teamA)
        let games = try XCTUnwrap(saved.games)
        XCTAssertEqual(games.count, 1, "the legacy game must not be dropped")
        let game = try XCTUnwrap(games.first)
        XCTAssertEqual(game.teamAFinalScore, 12)
        XCTAssertEqual(game.teamBFinalScore, 9)
        XCTAssertEqual(game.winningTeam, .teamA)
    }
```

(`makeInMemoryContext()` is the existing private helper in that file. `PickleballGame(configuration:state:history:proUnlocked:demoPointCap:)` and `GameState`'s memberwise init are public; `@testable import PickleballKit` is already at the top of the file.)

- [ ] **Step 2: Run to verify it fails**

Run (from `PickleballKit/`): `swift test --filter MatchRepositoryHistoryTests/testSaveCompletedMatchKeepsAGameWhoseScoreNoLongerCountsAsCompleted 2>&1 | grep -E "error:|Executed" | head`
Expected: FAIL — `games.count` is 0 (the game is dropped by the `continue`).

- [ ] **Step 3: Implement the fallback**

In `MatchRepository.saveCompletedMatch`, replace:

```swift
            guard let gameWinner = game.gameWinner else { continue }
```

with:

```swift
            // `gameWinner` is nil only for a game decided at a score the strict
            // completed-score rule no longer recognises (a legacy in-progress
            // snapshot). Fall back to the higher score rather than silently
            // dropping the game — it is already counted in `gamesWon`.
            let gameWinner = game.gameWinner
                ?? (game.state.teamAScore > game.state.teamBScore ? Team.teamA : Team.teamB)
```

Leave the rest of the loop body unchanged.

- [ ] **Step 4: Add the two Quick Log repository tests**

Add to `MatchRepositoryQuickLogTests` (inside the class, after `testSavedMatchAppearsInFetchMatchHistory`):

```swift
    func testTeamBWinningTheOnlyGameIsRecordedAsTheMatchWinner() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let saved = try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            gameScores: [(teamA: 7, teamB: 11)]
        )

        XCTAssertEqual(saved.winningTeam, .teamB)
        let game = try XCTUnwrap(saved.games?.first)
        XCTAssertEqual(game.winningTeam, .teamB)
        XCTAssertEqual(game.teamAFinalScore, 7)
        XCTAssertEqual(game.teamBFinalScore, 11)
    }

    func testAnEmptyGameScoresListThrowsMatchNotOver() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        XCTAssertThrowsError(try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            gameScores: []
        )) { error in
            XCTAssertEqual(error as? MatchRepositoryError, .matchNotOver)
        }
        XCTAssertTrue(try repository.fetchMatchHistory().isEmpty, "nothing may be saved on a rejected entry")
    }
```

- [ ] **Step 5: Run the full PickleballKit suite**

Run: `swift test 2>&1 | grep -E "Executed|error:|failed" | tail -3`
Expected: `Executed 156 tests, with 0 failures` (153 + 1 fallback + 2 Quick Log).

- [ ] **Step 6: Commit**

```bash
git add PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift PickleballKit/Tests/PickleballKitTests/MatchRepositoryHistoryTests.swift PickleballKit/Tests/PickleballKitTests/MatchRepositoryQuickLogTests.swift
git commit -m "$(cat <<'EOF'
Keep legacy decided games on save; add Quick Log repository test coverage

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `ActiveMatchController.correctScores`

**Files:**
- Modify: `ServerTwo/ActiveMatchController.swift` (add `correctScores` next to `correctScore`, ~line 204)
- Modify: `ServerTwoTests/ActiveMatchControllerTests.swift` (two call sites: `testCorrectScorePersistsSnapshot` ~line 195 and `testCorrectScoreGrowsGameCompletionDatesWhenItWinsAGame` ~line 506)

**Interfaces:**
- Consumes: `PickleballMatch.correctScores(teamA:teamB:)` from Task 2.
- Produces: `ActiveMatchController.correctScores(teamA: Int, teamB: Int)` — consumed by Task 5. The controller's single-team `correctScore(team:to:)` is KEPT for now (Task 5 removes it once `ScoringView` stops calling it), so every commit builds.

- [ ] **Step 1: Migrate and extend the controller tests (they fail to compile until Step 2)**

In `ServerTwoTests/ActiveMatchControllerTests.swift`, replace `testCorrectScorePersistsSnapshot`:

```swift
    func testCorrectScorePersistsSnapshot() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(controller, teamAName: "A", teamBName: "B")
        controller.correctScore(team: .teamA, to: 7)

        let reread = try MatchRepository(modelContext: ModelContext(container))
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: nil)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 7)
    }
```

with:

```swift
    func testCorrectScoresPersistsSnapshot() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(controller, teamAName: "A", teamBName: "B")
        controller.correctScores(teamA: 7, teamB: 4)

        let reread = try MatchRepository(modelContext: ModelContext(container))
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: nil)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 7)
        XCTAssertEqual(reread?.match.currentGame.state.teamBScore, 4)
    }
```

and replace `testCorrectScoreGrowsGameCompletionDatesWhenItWinsAGame` (including its doc comment) with:

```swift
    /// `correctScores(teamA:teamB:)` calls `syncGameCompletionDates()` the
    /// same as `recordPoint`/`undo`, but only those two call sites were
    /// covered by a test — this exercises the sync helper via the correction
    /// call site, including the two-team flow that motivated the atomic API:
    /// 9-9 -> 12-11 must NOT complete a game (no date), and 12-10 must.
    func testCorrectScoresGrowsGameCompletionDatesOnlyWhenItWinsAGame() throws {
        let (controller, _) = try makeController()
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        start(controller, configuration: config, matchFormat: .bestOfThree, teamAName: "A", teamBName: "B")
        XCTAssertEqual(controller.gameCompletionDates.count, 0)

        controller.correctScores(teamA: 9, teamB: 9)
        controller.correctScores(teamA: 12, teamB: 11)   // in progress: no game completed
        XCTAssertEqual(controller.match?.completedGames.count, 0)
        XCTAssertEqual(controller.gameCompletionDates.count, 0)

        controller.correctScores(teamA: 12, teamB: 10)   // completed: game 1 ends
        XCTAssertEqual(controller.match?.completedGames.count, 1)
        XCTAssertEqual(controller.gameCompletionDates.count, 1)
    }
```

- [ ] **Step 2: Add `correctScores` to the controller**

In `ServerTwo/ActiveMatchController.swift`, add this method directly after the existing `correctScore(team:to:)` (leave that method in place for now):

```swift
    func correctScores(teamA: Int, teamB: Int) {
        match?.correctScores(teamA: teamA, teamB: teamB)
        syncGameCompletionDates()
        persistSnapshot()
    }
```

and reword the comment on `syncGameCompletionDates` ("Called from `recordPoint`/`undo`/`correctScore` only") to say `correctScores`. (A correction moves `completedGames.count` by at most one in either direction, so the helper's grow/shrink-by-one assumption still holds.)

- [ ] **Step 3: Run the controller tests**

Run: `rm -rf /tmp/ctl.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -only-testing:ServerTwoTests/ActiveMatchControllerTests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath /tmp/ctl.xcresult > /tmp/ctl.log 2>&1; xcrun xcresulttool get test-results summary --path /tmp/ctl.xcresult | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:d.get(k) for k in ('result','passedTests','failedTests','totalTestCount')})"`
Expected: `Passed`, 0 failed.

- [ ] **Step 4: Commit**

```bash
git add ServerTwo/ActiveMatchController.swift ServerTwoTests/ActiveMatchControllerTests.swift
git commit -m "$(cat <<'EOF'
Add ActiveMatchController.correctScores and migrate its tests

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Two-score correction sheet, `ScoringView` wiring, and tests

**Files:**
- Modify: `ServerTwo/Scoring/ScoreCorrectionSheet.swift` (full rewrite, 49 lines today)
- Modify: `ServerTwo/ActiveMatchController.swift` (remove the single-team `correctScore(team:to:)`)
- Modify: `ServerTwo/Scoring/ScoringView.swift` (`correctingTeam` state ~line 8; the `.sheet` + `onDismiss` ~lines 59-96; the `.onChange(of: ...hasSideSwitched)` ~line 129; the long-press ~line 309)
- Create: `ServerTwoTests/ScoreCorrectionSheetTests.swift`
- Create: `ServerTwoUITests/ScoreCorrectionUITests.swift`

**Interfaces:**
- Consumes: `ActiveMatchController.correctScores(teamA:teamB:)` (Task 4), `GameConfiguration.isReachableGameScore` (Task 1).
- Produces: `ScoreCorrectionSheet` with static pure helpers `canSave(configuration:currentTeamA:currentTeamB:proposedTeamA:proposedTeamB:)` and `hintText(configuration:teamA:teamB:)`.

- [ ] **Step 1: Write the failing unit tests for the sheet's pure logic**

Create `ServerTwoTests/ScoreCorrectionSheetTests.swift`:

```swift
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
```

- [ ] **Step 2: Rewrite `ScoreCorrectionSheet`**

Replace the entire contents of `ServerTwo/Scoring/ScoreCorrectionSheet.swift` with:

```swift
import SwiftUI
import PickleballKit

/// Corrects BOTH teams' scores in one step. The engine applies the pair
/// atomically (`ActiveMatchController.correctScores`), and Save is only
/// enabled for a pair live play could actually be in — a one-team-at-a-time
/// edit used to pass through boards that ended the game early or left one
/// that could never end by scoring.
struct ScoreCorrectionSheet: View {
    let teamAName: String
    let teamBName: String
    let currentTeamAScore: Int
    let currentTeamBScore: Int
    let configuration: GameConfiguration
    let onCommit: (_ teamA: Int, _ teamB: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newTeamAScore: Int
    @State private var newTeamBScore: Int

    init(
        teamAName: String,
        teamBName: String,
        currentTeamAScore: Int,
        currentTeamBScore: Int,
        configuration: GameConfiguration,
        onCommit: @escaping (_ teamA: Int, _ teamB: Int) -> Void
    ) {
        self.teamAName = teamAName
        self.teamBName = teamBName
        self.currentTeamAScore = currentTeamAScore
        self.currentTeamBScore = currentTeamBScore
        self.configuration = configuration
        self.onCommit = onCommit
        _newTeamAScore = State(initialValue: currentTeamAScore)
        _newTeamBScore = State(initialValue: currentTeamBScore)
    }

    /// Save is off while the pair is unreachable (including when the CURRENT
    /// pair is already unreachable — the user must fix it) and while nothing
    /// has changed (avoids a junk undo entry).
    static func canSave(
        configuration: GameConfiguration,
        currentTeamA: Int, currentTeamB: Int,
        proposedTeamA: Int, proposedTeamB: Int
    ) -> Bool {
        let isUnchanged = proposedTeamA == currentTeamA && proposedTeamB == currentTeamB
        return !isUnchanged && configuration.isReachableGameScore(teamA: proposedTeamA, teamB: proposedTeamB)
    }

    static func hintText(configuration: GameConfiguration, teamA: Int, teamB: Int) -> String {
        let rule = configuration.winByTwo ? " (win by 2)" : ""
        return "\(teamA)–\(teamB) can't happen in a game to \(configuration.winningScore.rawValue)\(rule). Adjust either score."
    }

    private var isReachable: Bool {
        configuration.isReachableGameScore(teamA: newTeamAScore, teamB: newTeamBScore)
    }

    private var canSave: Bool {
        Self.canSave(
            configuration: configuration,
            currentTeamA: currentTeamAScore, currentTeamB: currentTeamBScore,
            proposedTeamA: newTeamAScore, proposedTeamB: newTeamBScore
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(teamAName): \(newTeamAScore)", value: $newTeamAScore, in: 0...99)
                        .accessibilityIdentifier("ScoreCorrection.TeamAStepper")
                    Stepper("\(teamBName): \(newTeamBScore)", value: $newTeamBScore, in: 0...99)
                        .accessibilityIdentifier("ScoreCorrection.TeamBStepper")
                }
                if !isReachable {
                    Section {
                        Text(Self.hintText(configuration: configuration, teamA: newTeamAScore, teamB: newTeamBScore))
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("ScoreCorrection.Hint")
                    }
                }
            }
            .navigationTitle("Correct Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("ScoreCorrection.Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onCommit(newTeamAScore, newTeamBScore)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("ScoreCorrection.Save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ScoreCorrectionSheet(
        teamAName: "Team A",
        teamBName: "Team B",
        currentTeamAScore: 9,
        currentTeamBScore: 9,
        configuration: GameConfiguration(),
        onCommit: { _, _ in }
    )
}
```

- [ ] **Step 3: Rewire `ScoringView`**

In `ServerTwo/Scoring/ScoringView.swift` make exactly these edits:

(a) Replace `    @State private var correctingTeam: Team?` with `    @State private var isShowingScoreCorrection = false`.

(b) Replace the sheet's presentation header and content. The current code:

```swift
        .sheet(isPresented: Binding(
            get: { correctingTeam != nil },
            set: { isPresented in if !isPresented { correctingTeam = nil } }
        ), onDismiss: {
```

becomes:

```swift
        .sheet(isPresented: $isShowingScoreCorrection, onDismiss: {
```

Keep the whole long explanatory comment inside `onDismiss` unchanged, and change its condition from

```swift
                if match.currentGame.state.hasSideSwitched, sideSwitchAcknowledgedViaCorrectionForGameIndex != gameIndex {
```

to

```swift
                if match.currentGame.state.hasSideSwitched, !match.isMatchOver, sideSwitchAcknowledgedViaCorrectionForGameIndex != gameIndex {
```

Then replace the sheet's content closure:

```swift
            if let match = activeMatchController.match, let team = correctingTeam {
                ScoreCorrectionSheet(
                    teamDisplayName: team == .teamA ? activeMatchController.teamAName : activeMatchController.teamBName,
                    currentScore: match.currentGame.state.score(for: team),
                    onCommit: { newScore in
                        activeMatchController.correctScore(team: team, to: newScore)
                    }
                )
            }
```

with:

```swift
            if let match = activeMatchController.match {
                ScoreCorrectionSheet(
                    teamAName: activeMatchController.teamAName,
                    teamBName: activeMatchController.teamBName,
                    currentTeamAScore: match.currentGame.state.teamAScore,
                    currentTeamBScore: match.currentGame.state.teamBScore,
                    configuration: match.configuration,
                    onCommit: { teamA, teamB in
                        activeMatchController.correctScores(teamA: teamA, teamB: teamB)
                    }
                )
            }
```

(c) In the `.onChange(of: activeMatchController.match?.currentGame.state.hasSideSwitched)` handler, change

```swift
            if hasSideSwitched == true, sideSwitchAcknowledgedForGameIndex != gameIndex {
```

to

```swift
            if hasSideSwitched == true, !match.isMatchOver, sideSwitchAcknowledgedForGameIndex != gameIndex {
```

(d) Replace the long-press `        .onLongPressGesture {\n            correctingTeam = team\n        }` with:

```swift
        .onLongPressGesture {
            isShowingScoreCorrection = true
        }
```

Leave the score zone's `.accessibilityLabel` (`"... Tap to score, double tap and hold to correct."`) unchanged.

(e) Now that nothing calls it, REMOVE the controller's single-team method from `ServerTwo/ActiveMatchController.swift`:

```swift
    func correctScore(team: Team, to newScore: Int) {
        match?.correctScore(team: team, to: newScore)
        syncGameCompletionDates()
        persistSnapshot()
    }
```

First run `grep -rn "correctScore(team" ServerTwo ServerTwoTests` — the only hit left must be the method itself (the `PickleballMatch`/`PickleballGame` single-team methods are called only from `PickleballKit` and its tests, outside these directories). If any other caller of the CONTROLLER's single-team method turns up, migrate it to `correctScores` instead of keeping the method.

- [ ] **Step 4: Build and run the new unit tests**

Run: `xcodebuild build -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' 2>&1 | tail -3` → expect `** BUILD SUCCEEDED **`.

Run: `rm -rf /tmp/sc-unit.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -only-testing:ServerTwoTests/ScoreCorrectionSheetTests -only-testing:ServerTwoTests/ActiveMatchControllerTests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath /tmp/sc-unit.xcresult > /tmp/sc-unit.log 2>&1; xcrun xcresulttool get test-results summary --path /tmp/sc-unit.xcresult | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:d.get(k) for k in ('result','passedTests','failedTests','totalTestCount')})"`
Expected: `result: Passed`, 0 failed (includes the migrated controller tests and the 7 new sheet tests).

- [ ] **Step 5: Write the single UI test**

Create `ServerTwoUITests/ScoreCorrectionUITests.swift`:

```swift
import XCTest

final class ScoreCorrectionUITests: XCTestCase {
    func testTwoScoreCorrectionGatesSaveOnReachabilityAndAppliesBothScoresAtOnce() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Start a match with default rules (side-out, 11 points, win by 2); names
        // stay blank so the Team A / Team B fallback applies.
        app.tabBars.buttons["Play"].tap()
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()
        let flipCoinButton = app.buttons["Flip Coin"]
        XCTAssertTrue(flipCoinButton.waitForExistence(timeout: 3))
        flipCoinButton.tap()
        let beginMatchButton = app.buttons["Begin Match"]
        XCTAssertTrue(beginMatchButton.waitForExistence(timeout: 3))
        beginMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        let teamBZone = app.buttons["scoreZone.teamB"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 3))

        // Long-press either score zone to open the two-score sheet.
        teamAZone.press(forDuration: 1.0)
        let save = app.buttons["ScoreCorrection.Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))

        let teamAStepper = app.steppers["ScoreCorrection.TeamAStepper"]
        let teamBStepper = app.steppers["ScoreCorrection.TeamBStepper"]

        // Starts at the current scores (0-0): nothing changed, so Save is off
        // and there is no hint.
        XCTAssertTrue(teamAStepper.label.hasSuffix(": 0"), "got \(teamAStepper.label)")
        XCTAssertTrue(teamBStepper.label.hasSuffix(": 0"), "got \(teamBStepper.label)")
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(app.staticTexts["ScoreCorrection.Hint"].exists)

        // Team A to 12 while B is 0: 12-0 can't happen in a game to 11 (win by 2).
        for _ in 0..<12 { teamAStepper.buttons["Increment"].tap() }
        XCTAssertTrue(app.staticTexts["ScoreCorrection.Hint"].waitForExistence(timeout: 2))
        XCTAssertFalse(save.isEnabled)

        // Team B to 11: 12-11 is a legitimate in-progress score — hint gone, Save on.
        // (Passing through 12-10, a completed final, is fine: nothing is saved yet.)
        for _ in 0..<11 { teamBStepper.buttons["Increment"].tap() }
        XCTAssertFalse(app.staticTexts["ScoreCorrection.Hint"].exists)
        XCTAssertTrue(save.isEnabled)

        save.tap()

        // The correction crosses the side-switch threshold on an in-progress
        // game, so the alert legitimately appears.
        // Asserted (not optional): this also proves the new `!match.isMatchOver`
        // guard does not suppress the alert for an in-progress game.
        let sideSwitchAlert = app.alerts["Side Switch"]
        XCTAssertTrue(sideSwitchAlert.waitForExistence(timeout: 5), "the correction crosses the side-switch threshold on a live game")
        sideSwitchAlert.buttons["OK"].tap()

        // Both scores applied at once, and the game did NOT end mid-edit.
        XCTAssertTrue(teamAZone.label.contains("12 points"), "got \(teamAZone.label)")
        XCTAssertTrue(teamBZone.label.contains("11 points"), "got \(teamBZone.label)")
        XCTAssertTrue(teamAZone.isEnabled)
        XCTAssertTrue(teamBZone.isEnabled)
    }
}
```

- [ ] **Step 6: Run the UI test**

Run: `rm -rf /tmp/sc-ui.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -only-testing:ServerTwoUITests/ScoreCorrectionUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath /tmp/sc-ui.xcresult > /tmp/sc-ui.log 2>&1; xcrun xcresulttool get test-results summary --path /tmp/sc-ui.xcresult | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:d.get(k) for k in ('result','passedTests','failedTests','totalTestCount')})"`
Expected: `Passed`, 1 test. If it fails, do NOT iterate more than twice: read `xcrun xcresulttool get test-results tests --path /tmp/sc-ui.xcresult` for the failing assertion and report it. Known adaptations that ARE allowed without escalating (report them): if a stepper's `label` doesn't end with `": 0"` but exposes the number via `value`, assert on `value` instead; if `press(forDuration:)` doesn't open the sheet, try a longer duration. If the xcodebuild process hangs after the tests finish, `pkill -f xcodebuild` and read the bundle.

- [ ] **Step 7: Commit**

```bash
git add ServerTwo/ActiveMatchController.swift ServerTwo/Scoring/ScoreCorrectionSheet.swift ServerTwo/Scoring/ScoringView.swift ServerTwoTests/ScoreCorrectionSheetTests.swift ServerTwoUITests/ScoreCorrectionUITests.swift
git commit -m "$(cat <<'EOF'
Two-score correction sheet gated by reachability; suppress Side Switch on a finished match

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Quick Log cleanups and final verification

**Files:**
- Modify: `ServerTwo/Setup/MatchSetupView.swift` (`QuickLogState`'s stored properties ~lines 36-37; `startMatch()` ~lines 585-599; `scheduleQuickLogCommit` ~lines 754-770; `saveQuickLoggedMatch` ~lines 853-880)

**Interfaces:** consumes nothing from earlier tasks; produces nothing later tasks use.

**Deliberately omitted:** the spec's "Save-disabled assertion after an invalidating edit in the row-visibility test" — in the row test's best-of-3 flow Save is disabled both before and after an invalidating Game 1 edit (a single game never decides a best-of-3), so the assertion would pass vacuously and test nothing. A meaningful version needs a new best-of-1 UI test with text replacement, which is not worth its simulator cost here. (`testLoggingAFinalScore…` already asserts Save is ENABLED once a score decides the match.)

- [ ] **Step 1: Expose `QuickLogState`'s config and use it as the single source**

In `QuickLogState`, change

```swift
    private let matchFormat: MatchFormat
    private let configuration: GameConfiguration
```

to

```swift
    let matchFormat: MatchFormat
    let configuration: GameConfiguration
```

In `scheduleQuickLogCommit`, change

```swift
        guard let entry = quickLogState?.entries.first(where: { $0.id == gameID }) else { return }
```

to

```swift
        guard let state = quickLogState, let entry = state.entries.first(where: { $0.id == gameID }) else { return }
```

and change the ambiguity call's argument `configuration: quickLogConfiguration` to `configuration: state.configuration`.

In `saveQuickLoggedMatch`, change the repository call's `configuration: quickLogConfiguration,` to `configuration: state.configuration,` and `matchFormat: matchFormat,` to `matchFormat: state.matchFormat,`. (`quickLogConfiguration` is still used by `presentQuickLogSheet()` — leave it.)

- [ ] **Step 2: Extract the duplicated players-by-play-mode logic**

Add this private method to `MatchSetupView`, next to `resolvedPlayers(_:)`:

```swift
    /// Resolves both teams' players from the typed name fields — one player per
    /// side in singles, two in doubles. Shared by `startMatch()` and
    /// `saveQuickLoggedMatch()`.
    private func resolvedTeamPlayers() -> (teamA: [SavedPlayer], teamB: [SavedPlayer]) {
        let teamA = playMode == .doubles
            ? resolvedPlayers((teamAPlayer1, teamAPlayer1ID), (teamAPlayer2, teamAPlayer2ID))
            : resolvedPlayers((teamAPlayer1, teamAPlayer1ID))
        let teamB = playMode == .doubles
            ? resolvedPlayers((teamBPlayer1, teamBPlayer1ID), (teamBPlayer2, teamBPlayer2ID))
            : resolvedPlayers((teamBPlayer1, teamBPlayer1ID))
        return (teamA, teamB)
    }
```

In `startMatch()`, replace the two `let teamAPlayers = …` / `let teamBPlayers = …` ternaries with `let players = resolvedTeamPlayers()` and use `players.teamA.map(\.id)` / `players.teamB.map(\.id)` in the `PendingMatchSetup`. In `saveQuickLoggedMatch()`, do the same and pass `teamAPlayers: players.teamA, teamBPlayers: players.teamB`.

- [ ] **Step 3: Build and run the Quick Log UI tests**

Run: `rm -rf /tmp/ql-clean.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -only-testing:ServerTwoUITests/QuickLogUITests -only-testing:ServerTwoUITests/QuickLogRowVisibilityUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath /tmp/ql-clean.xcresult > /tmp/ql-clean.log 2>&1; xcrun xcresulttool get test-results summary --path /tmp/ql-clean.xcresult | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:d.get(k) for k in ('result','passedTests','failedTests','totalTestCount')})"`
Expected: `Passed`, 5 tests.

- [ ] **Step 4: Commit**

```bash
git add ServerTwo/Setup/MatchSetupView.swift
git commit -m "$(cat <<'EOF'
Quick Log: single config source and shared team-player resolution

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Final verification — run everything once**

Run `swift test 2>&1 | grep -E "Executed|error:|failed" | tail -3` from `PickleballKit/` → expect `Executed 156 tests, with 0 failures`.

Run the FULL app suite once: `rm -rf /tmp/sc-full.xcresult; xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -resultBundlePath /tmp/sc-full.xcresult > /tmp/sc-full.log 2>&1; xcrun xcresulttool get test-results summary --path /tmp/sc-full.xcresult | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:d.get(k) for k in ('result','passedTests','failedTests','totalTestCount')}); [print(f.get('testName'),'|',f.get('failureText')) for f in d.get('testFailures',[])]"`
Expected: `Passed`, 61 tests (53 existing + 7 `ScoreCorrectionSheetTests` + 1 `ScoreCorrectionUITests`), 0 failures. (The two migrated controller tests keep the count unchanged: one was renamed, one was renamed and extended.) If a test fails, re-run only that test once on a freshly warmed simulator before reporting it as a failure — this project has had environment-caused one-off failures.

---

## Self-Review

**Spec coverage:** reachability rule + hand-checked cases (Task 1, incl. 15/21, win-by-2 off, freeze); atomic `PickleballGame.correctScores` with the single-team method reimplemented over it (Task 1); atomic `PickleballMatch.correctScores`, the extracted `reconcileCurrentGame`, and the undo Branch 1/2 fix with fail-first tests for un-count/flip/same-winner (Task 2); controller `correctScores`, single-team controller method removed, two test call sites migrated, completion-date sync test (Task 4); two-stepper sheet, Save gating (unreachable OR unchanged), hint, identifiers, dropped `maxScore`, current-pair-stuck recovery (Task 5); `ScoringView` `isShowingScoreCorrection` + both `!match.isMatchOver` side-switch guards + unchanged `onDismiss` fallback (Task 5); the one UI test with per-stepper-scoped Increment buttons, hint by identifier, Side Switch alert dismissal (Task 5); `saveCompletedMatch` winner fallback + test (Task 3); Quick Log single config source, players helper, Team B / empty `gameScores` tests (Tasks 3 and 6). The spec's "Save-disabled assertion in the row-visibility test" is deliberately omitted (reason stated in Task 6) and the spec should be read with that one change. Spec non-goals are respected: undo Branch 3, archived-game editing, freeze serve-order and timeouts/serving correction are untouched.

**Placeholder scan:** no TBD/TODO; every code step has complete code and every run step an exact command and expected result.

**Type consistency:** `isReachableGameScore(teamA:teamB:)` (Task 1) is called identically from `ScoreCorrectionSheet` (Task 5). `PickleballGame.correctScores(teamA:teamB:)` (Task 1) is called by `PickleballMatch.correctScores` (Task 2), which `ActiveMatchController.correctScores` (Task 4) calls, which `ScoringView`'s sheet closure (Task 5) calls with `(teamA, teamB)`. `canSave(configuration:currentTeamA:currentTeamB:proposedTeamA:proposedTeamB:)` and `hintText(configuration:teamA:teamB:)` are defined in the sheet and called with matching labels by `ScoreCorrectionSheetTests`.

**Review Focus:** each of the five lines is tied to a named test in its owning task (listed in Review Focus above).

**Count arithmetic:** PickleballKit 128 → +9 (reachability) +7 (game correctScores) = 144 → +9 (match) = 153 → +3 (fallback, Team B, empty) = 156. App suite 53 → +7 sheet tests +1 UI test = 61 (the two migrated controller tests replace two existing ones one-for-one).
