# Atomic Two-Score Correction Design

**Goal:** Make correcting a live game's score reliable: a user fixing a disputed score sets BOTH teams' scores in one step, and can never leave the game in a state that ends prematurely mid-edit or can never end by scoring.

## Context

Found during the Quick Log final review, then verified against the code (every fact below was read, not assumed).

**How correction works today**
- Entry point: a long-press on either team's score zone in `ScoringView` (`.onLongPressGesture { correctingTeam = team }`) opens `ScoreCorrectionSheet`.
- `ScoreCorrectionSheet` edits ONE team: a single `Stepper` (0...maxScore, default 99). Save calls `onCommit(newScore)` for that one team only.
- Path: `ActiveMatchController.correctScore(team:to:)` → `PickleballMatch.correctScore(team:to:)` → `PickleballGame.correctScore(team:to:)`. The game sets the one score directly, runs `checkSideSwitch()`, sets `lastPointWonWhileServing = true`, and appends ONE undo-history entry first.
- `PickleballMatch.correctScore` evaluates `currentGame.gameWinner` immediately after that single write. If the game is now won it archives it into `completedGames`, bumps `gamesWon`, and (if the match isn't over) replaces `currentGame` with a fresh 0-0 game.
- The score zones are `.disabled(match.isMatchOver)`, so the UI can only correct an in-progress game; the engine's "un-count a decided game" paths are reachable only from tests/undo.

**The problem.** A realistic two-team correction passes through an intermediate board that the engine acts on:
- 9-9 → fix to 12-11: the first write gives 12-9. Under the old lenient rule that ended the game for A mid-edit; in a best-of-3, Game 1 is archived and Game 2 starts before B can be fixed (only `currentGame` is editable afterwards).
- Under the strict rule (`GameConfiguration.isCompletedGameScore`, added by Quick Log) 12-9 is not a completed score AND not reachable by more points (the leader goes 13-9, 14-9, never exactly +2): a "zombie" game only a trailing-team comeback can end. With win-by-2 OFF, any score above the target can never end by points at all.
- 13-12 → 11-10: the first write gives 13-11, a completed score under both rules, so the game ends mid-edit.

**Root cause:** single-team editing + engine acting after each write. Hint, clamp, and "lenient corrections" were each considered and rejected (a hint false-positives on the legitimate first step of a two-step edit; a clamp blocks legitimate edits like 9-9 → 14-13; lenient ends the game mid-edit and lets illegal finals like 15-9 into history).

## Design

### 1. Reachability rule — `GameConfiguration.isReachableGameScore(teamA:teamB:)`
Whether a score pair is a state live play could actually be in: either a legal completed final or a legal in-progress score.

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
Hand-checked cases (11-point game): `12-9` unreachable (margin 3, overtime, not completed); `12-11`, `11-11`, `11-10` reachable in-progress (win-by-2); `11-9`, `12-10`, `13-11` reachable completed; `3-0` reachable; negative unreachable. Win-by-2 OFF: `11-10` completed/reachable; `12-10`, `11-11`, `12-12` unreachable (the game would already have ended at 11). Freeze: any non-negative pair reachable.

### 2. Atomic engine API
- `PickleballGame.correctScores(teamA:teamB:)` — ONE history append, clamp each to ≥0, set both, ONE `checkSideSwitch()`, `lastPointWonWhileServing = true`. Does NOT validate reachability (engine trusts the caller, same as today; the UI gates).
- `PickleballGame.correctScore(team:to:)` is reimplemented on top of it (`correctScores(teamA: team == .teamA ? newScore : state.teamAScore, teamB: team == .teamB ? newScore : state.teamBScore)`) — behavior identical, so every existing test passes unchanged.
- `PickleballMatch.correctScores(teamA:teamB:)` — the existing `correctScore(team:to:)` body moved over verbatim (`wasCounted`/`previousWinner` logic, archive/un-archive, new-game creation, match-over transitions), calling `currentGame.correctScores(...)`. `correctScore(team:to:)` forwards to it. The win/loss bookkeeping is evaluated ONCE, after both scores are set — which is the whole point.
- Undo: the game gets ONE history entry per atomic correction, so one undo restores both scores. The existing `PickleballMatch.undo()` branches (counted game / current game history / pop previous completed game) already restore via `currentGame.undo()` and need no change; tests must cover each branch with an atomic correction.
- `ActiveMatchController.correctScores(teamA:teamB:)` mirrors `correctScore`: call the match, `syncGameCompletionDates()`, `persistSnapshot()`. Its existing comment ("each of those can move `completedGames.count` by exactly one in either direction") stays true. `correctScore(team:to:)` on the controller stays as a thin wrapper (its existing tests call it).

### 3. UI — one sheet, both teams
- `ScoringView`: replace `@State correctingTeam: Team?` with `@State isShowingScoreCorrection = false`; a long-press on EITHER score zone sets it. The `onDismiss` side-switch fallback is kept exactly as is (it already reads the match, not `correctingTeam`).
- `ScoreCorrectionSheet` becomes a two-stepper "Correct Score" sheet: `teamAName`, `teamBName`, `currentTeamAScore`, `currentTeamBScore`, `configuration: GameConfiguration`, `onCommit: (Int, Int) -> Void`. Drop the unused `maxScore` parameter (always 99; no caller tightens it). Steppers start at the current scores, range 0...99.
- Save is disabled when the pair is unreachable (`configuration.isReachableGameScore`) OR unchanged from the current scores (avoids junk undo entries). When unreachable, a hint shows: "`12–9` can't happen in a game to 11 (win by 2). Adjust either score." (win-by-2 text only when enabled; never shown for freeze since freeze is always reachable).
- Recovery from an already-stuck game: if the CURRENT pair is unreachable (a zombie left by the old rules in a saved in-progress game), Save is disabled until the user fixes the pair — the sheet is the escape hatch.
- Known SwiftUI traps from Quick Log: read the scores/names/configuration in the sheet content at presentation time from the live `activeMatchController.match` (as today); the sheet struct snapshots them into `@State` in `init`. The initial stepper values being correct is covered by the UI test.
- Accessibility identifiers: `ScoreCorrection.TeamAStepper`, `ScoreCorrection.TeamBStepper`, `ScoreCorrection.Hint`, `ScoreCorrection.Save`, `ScoreCorrection.Cancel`.

### 4. Related items folded in (decided here)
**Included**
- *Defensive winner fallback in `MatchRepository.saveCompletedMatch`.* It currently does `guard let gameWinner = game.gameWinner else { continue }`, silently DROPPING a completed game whose stored score the strict rule no longer recognizes (only possible via an in-progress snapshot saved before the strict rule landed, with a game completed at a now-impossible corrected score). Fix: fall back to the higher score as the winner (`game.gameWinner ?? (a > b ? .teamA : .teamB)`), so no game is lost and it matches `gamesWon`. `PickleballMatch.undo()` is deliberately NOT changed for this case (stale count after undoing past such a game is rarer still and touches core undo paths; documented as accepted).
- *Quick Log single config source:* expose `QuickLogState.configuration`/`matchFormat` and use them for ambiguity classification and for the repository save, instead of the live form values.
- *Quick Log duplicated players ternary:* extract one private helper in `MatchSetupView` used by `startMatch()` and `saveQuickLoggedMatch()`.
- *Quick Log test-coverage gaps (cheap, no new UI runs):* `saveQuickLoggedMatch` with Team B winning, and with empty `gameScores` (expects `.matchNotOver`); a `Save`-disabled assertion after an invalidating edit in the existing row-visibility test.

**Excluded, with reasons**
- `.interactiveDismissDisabled` for a Quick Log sheet with typed text — silently refusing a swipe is worse UX than the current behavior; the right fix would be a discard confirmation, a separate product decision.
- Quick Log doubles-mode / suggestion-chip UI coverage — expensive UI tests for a path that shares the already-tested `resolvedPlayers` helper.
- Non-ASCII digits via `filter(\.isNumber)` and leading zeros ("05") — `Int()` safely rejects/normalizes them; no user-visible effect.

## Testing
- `PickleballKitTests`: new `GameConfigurationReachableScoreTests` covering the hand-checked cases above (incl. freeze, win-by-2 off, scores already past target, negatives, 15/21-point targets); `PickleballGame.correctScores` (both scores set, ONE undo restores both, clamps negatives, side-switch crossing via either team, `lastPointWonWhileServing` set); `PickleballMatch.correctScores` (the 9-9 → 12-11 flow produces NO game end and ends in the right state; 12-10 completes and archives; best-of-3 archive + new game; flip of a counted game's winner; un-count a counted game; ONE undo after each of those restores both scores and the bookkeeping; `correctScore(team:to:)` forwarding behaves as before); `saveCompletedMatch` winner fallback with a restored match whose completed game holds a now-impossible score; Team B winning and empty `gameScores` for `saveQuickLoggedMatch`.
- `ServerTwoTests`: `ActiveMatchController.correctScores` syncs `gameCompletionDates` the same way the single-team test does.
- ONE UI test, `ScoreCorrectionUITests` (deterministic, no long play): start a match, long-press a score zone; assert steppers start at 0/0 and Save is disabled (unchanged), no hint; raise A to 12 → hint exists and Save disabled; raise B to 11 → hint gone and Save enabled; Save → dismiss the "Side Switch" alert (the correction crosses the threshold; its button is "OK") → score zones read 12 and 11 and are still enabled (game not ended). Steppers are driven by the `Increment` buttons.

## Non-goals
- Editing an already-archived (earlier) game of a best-of-N match — still only the current game is correctable; undo remains the way back.
- Validating freeze serve order or tightening freeze margins (same documented gap as Quick Log).
- Correcting timeouts, serving team, or server number.
- A discard-confirmation flow for Quick Log's swipe-dismiss.
