# Post-Match Quick Log Design

**Goal:** Let a player record a match that already happened — phone was in their bag during play — by entering each game's final score directly, instead of the only option today (live, point-by-point tapping through `ScoringView`).

## Context

Second of four specs from a feature-backlog review (first was Chemistry Stats & Game Duration). Two things distinguish this one from the first: it needs **zero schema changes** (`GameRecord.points` already defaults to empty — no new field required), but it **does** touch the live scoring engine, unlike the first — specifically, it extracts an existing validation rule out of `PickleballGame` so Quick Log can reuse it rather than duplicate it. That extraction is flagged explicitly below since engine code deserves more scrutiny than a UI-only addition.

## What it does

`MatchSetupView` gains a secondary action — "Log Final Score Instead" — next to the primary "Start Match" CTA. It's visually secondary (a text button, not competing with the pinned CTA), the same relationship "Already spun a paddle?" has to the main flow on `CoinFlipView`.

Tapping it opens a sheet (matching the established sheet-over-alert pattern already used for Rename/Add Player — `.alert` with embedded input is the one pattern this codebase has already found unreliable in XCUITest). The sheet shows:

- The already-entered Team A / Team B names, read-only.
- Up to `(matchFormat.gamesToWin * 2) - 1` rows (the most games that format could ever need — 1 for Best of 1, 3 for Best of 3, 5 for Best of 5), each with two number-pad text fields (Team A score, Team B score). Scores run into the teens (13-11, 15-13, 21-19 are all legal depending on configuration), so a `Stepper` would take too many taps — a numeric keyboard is the right input for "quick."
- **Validation only runs on commit, not on every keystroke.** Validating live per-character would mean a user typing the two digits of "13" passes through "1" first — `isCompletedGameScore(teamA: 11, teamB: 1)` is `true`, so a naive live-validating row would briefly think Team A just won 11-1, spawn the next row, and potentially mislabel the match as decided, before the second digit even lands. Each field commits its value `onSubmit` (returning from the keyboard) or when the sheet's layout needs an answer (tapping into a different row), not on every character.
- A row is only ever **visible** (not destroyed) up to the point the match is decided or the previous row holds a valid, completed, committed score — "visible row count" is a pure computed value over the committed scores entered so far, recomputed on every commit, never a destructive mutation of stored state. Typed-but-not-yet-committed text in a row that becomes temporarily hidden is preserved underneath, not lost — editing Game 1 and briefly producing an invalid intermediate score never discards whatever was already entered for Game 2 or Game 3.
- "Save" is disabled until the match is actually decided (someone has reached `matchFormat.gamesToWin` based on committed, valid rows) — a half-entered match can't be saved as "complete" history, the same constraint live play already enforces via `MatchRepositoryError.matchNotOver`.
- The button (or the sheet's "Save") is gated by `activeMatchController.canStartNewMatch`, exactly like "Start Match" already is — presenting the same paywall sheet if a free user has used up `demoMatchLimit`. Quick Log bypasses `ActiveMatchController`'s match lifecycle entirely, but not its demo-limit gate; without this, it would be an unlimited free-tier loophole around the paywall.

On save, this bypasses `PickleballMatch`/`ActiveMatchController`'s match lifecycle entirely and writes straight to SwiftData via a new, dedicated repository method (see below) — there is no live match to drive, and no point-by-point log to produce (`GameRecord.points` stays empty for every game, exactly like the original backlog framing: "no point-by-point log").

After a successful save, the sheet dismisses and `MatchSetupView` resets its own name/selection `@State` back to blank. This mirrors — rather than invents — what already happens after a *live* match: `RootTabView`'s `playTabContent` shows `ScoringView` while a match is active and `MatchSetupView` while none is, as two different branches of a `@ViewBuilder` conditional; leaving the `MatchSetupView` branch while scoring live and returning to it after `finishMatch()` tears down and rebuilds the view, which is what naturally clears its fields today — not any explicit reset code. Since Quick Log's sheet never leaves `MatchSetupView` (no live match is ever created), there's no natural teardown to rely on, so the reset has to be explicit here. The user stays on the Play tab, same as after finishing a live match — no new auto-navigate-to-History behavior invented for this one path.

### Timestamps

Both `startedAt` and `completedAt` default to `Date()` at the moment of saving — the match genuinely happened earlier, but there's no live timing data to recover, and asking "when did you actually play?" adds a required field to the one screen explicitly meant to minimize friction. Because both values are identical, `completedAt.timeIntervalSince(startedAt) == 0` always, which the match-duration badge (from the Chemistry/Game Duration spec) would otherwise render as "< 1 min" — technically accurate, but reads as "this match took under a minute," which looks like a bug rather than "we don't know." `MatchDetailView`'s duration badge is updated to omit itself entirely when the computed duration is exactly zero, the same "nothing to report" treatment Feature 1's chemistry rows already use for a relationship that never happened.

## Score validation: extracting the shared rule

`PickleballGame.gameWinner` already implements "is this score combination a completed game" for live play:

```swift
public var gameWinner: Team? {
    let a = state.teamAScore
    let b = state.teamBScore
    let target = configuration.winningScore.rawValue
    guard max(a, b) >= target, a != b else { return nil }
    if configuration.winByTwo && abs(a - b) < 2 { return nil }
    let leader: Team = a > b ? .teamA : .teamB
    if case .rally(let freeze) = configuration.scoringFormat, freeze {
        guard state.lastPointWonWhileServing else { return nil }
    }
    return leader
}
```

The first three checks (score reached, not tied, win-by-2 if configured) look like pure functions of the two final scores and the configuration — but as written, they're looser than they should be once applied outside live play. Live play never exercises that looseness: `recordPoint` increments one score at a time and immediately stops once `gameWinner` is non-nil (`PickleballGame.isGameOver` gates every further call), so a live-played game can never reach an "impossible" state like 15-3 in an 11-point game — the game would have already ended at 11-anything. Quick Log has no such guarantee; it's validating free-typed integers that could be anything.

**The real upper-bound rule, and the one format where it doesn't apply:** past the first point that could have won (`winner > winningScore.rawValue`, i.e. genuine overtime), every format *except* `.rally(freeze: true)` halts the instant the win condition is first met, so an overtime final score can only ever have a margin of *exactly* 2 (without `winByTwo`, `winner` can never exceed the target at all, since the very point reaching it always ends the game). `.rally(freeze: true)` is the one format where a point can satisfy the score-based win condition while being won on receive — which does **not** end the game, since `gameWinner` additionally requires `lastPointWonWhileServing`. Play continues until the winning point is also won on serve, so under freeze, the final margin is not bounded at exactly 2 — it could legitimately be 2, 3, 4, or more. (Verified by tracing `recordPoint`/`recordRallyPoint`/`gameWinner` directly, not assumed.) Quick Log already can't validate freeze's serve-order requirement at all (no point history exists for an after-the-fact entry) — leaving the margin unconstrained under freeze is the same gap, not a new one, and is documented in Non-goals below.

**Extracted into `GameConfiguration`** (`PickleballKit/Sources/PickleballKit/GameConfiguration.swift`), so both call sites share one source of truth instead of two copies of the same rule drifting apart:

```swift
/// Whether `teamA`/`teamB` represents a legal *completed* game's final
/// score under this configuration's win condition — not merely "the
/// win-by-2/winning-score thresholds are currently satisfied" (which
/// live play never needs to distinguish from "and could only have
/// gotten here through a legal sequence of single points," since
/// `PickleballGame.recordPoint` physically cannot overshoot). An
/// after-the-fact score entry (Quick Log) has no such guarantee, so this
/// also rejects negative scores and impossible overtime margins (e.g.
/// 15-10 in an 11-point win-by-2 game — the game would have already
/// ended at 11-9 or 12-10).
///
/// Deliberately does NOT evaluate `.rally(freeze: true)`'s "won on
/// serve" rule, or constrain its overtime margin — both depend on live
/// serve-sequence state this pure score check has no access to.
/// `PickleballGame.gameWinner` layers the serve-order check on top for
/// live play; this is for validating an already-known final score with
/// no serve history (e.g. Quick Log).
public func isCompletedGameScore(teamA: Int, teamB: Int) -> Bool {
    guard teamA >= 0, teamB >= 0, teamA != teamB else { return false }
    let winner = max(teamA, teamB)
    let loser = min(teamA, teamB)
    guard winner >= winningScore.rawValue else { return false }
    if winByTwo, winner - loser < 2 { return false }
    guard winner > winningScore.rawValue else { return true }  // not overtime — above checks suffice
    if case .rally(let freeze) = scoringFormat, freeze { return true }  // see doc comment
    return winByTwo && (winner - loser == 2)
}
```

`PickleballGame.gameWinner` is refactored to call this for its first two checks:

```swift
public var gameWinner: Team? {
    let a = state.teamAScore
    let b = state.teamBScore
    guard configuration.isCompletedGameScore(teamA: a, teamB: b) else { return nil }
    let leader: Team = a > b ? .teamA : .teamB
    if case .rally(let freeze) = configuration.scoringFormat, freeze {
        guard state.lastPointWonWhileServing else { return nil }
    }
    return leader
}
```

**This is not a behavior-preserving refactor for every caller, and that's worth being explicit about.** For `recordPoint`-driven live play, it genuinely is identical — a live game can never reach a score `isCompletedGameScore` newly rejects. But `correctScore` (the live manual score-correction feature) lets a user type *any* score directly, with no path-of-single-points constraint — today, correcting a score to something like 15-10 in an 11-point win-by-2 game would be accepted by the old, looser checks as a valid win. After this change, that correction would no longer register as a completed game. This is a deliberate tightening, not an accident: a correction to a mathematically unreachable score was always a latent bug in `correctScore`, just one none of the existing tests happened to exercise. `PickleballKitTests`' existing `gameWinner` coverage (win-by-2, exact-score, rally-freeze cases) still needs to pass unchanged as a regression guard, but a new test case covering `correctScore` to an impossible overtime margin — confirming it's now correctly rejected rather than silently accepted — should be added alongside the extraction, not left as a side effect nobody wrote a test for.

## New repository method

```swift
/// A match recorded after the fact from final scores alone, with no
/// point-by-point log — bypasses `PickleballMatch` entirely since there's
/// no live match to drive. `gameScores` must be non-empty and its last
/// entry must decide the match (one team reaching `matchFormat
/// .gamesToWin`); earlier entries must each be a legal completed game
/// per `configuration.isCompletedGameScore` — both are caller
/// responsibilities (the Quick Log UI validates as the user types, this
/// method trusts that and just asserts via `MatchRepositoryError
/// .matchNotOver`/`.invalidGameScore` if violated, the same defensive
/// posture `saveCompletedMatch` already has for `matchNotOver`).
@discardableResult
public func saveQuickLoggedMatch(
    configuration: GameConfiguration,
    matchFormat: MatchFormat,
    teamAName: String,
    teamBName: String,
    gameScores: [(teamA: Int, teamB: Int)],
    teamAPlayers: [SavedPlayer] = [],
    teamBPlayers: [SavedPlayer] = [],
    completedAt: Date = Date()
) throws -> MatchRecord
```

Internals mirror `saveCompletedMatch`'s existing object-graph construction (explicit `modelContext.insert` for every object, never relying on cascade-insert through a relationship — see that function's own comment on why) but build each `GameRecord` directly from a `(teamA: Int, teamB: Int)` pair instead of from a `PickleballGame`:

```swift
var gamesWon: [Team: Int] = [.teamA: 0, .teamB: 0]
var gameRecords: [GameRecord] = []
for (index, score) in gameScores.enumerated() {
    // A game entry after the match was already decided (e.g. a 3rd game
    // for a Best of 3 that's already 2-0) is as invalid as a bad score —
    // without this, extra trailing entries would silently inflate
    // gamesWon past matchFormat.gamesToWin and still "succeed."
    guard gamesWon[.teamA, default: 0] < matchFormat.gamesToWin,
          gamesWon[.teamB, default: 0] < matchFormat.gamesToWin else {
        throw MatchRepositoryError.invalidGameScore
    }
    guard configuration.isCompletedGameScore(teamA: score.teamA, teamB: score.teamB) else {
        throw MatchRepositoryError.invalidGameScore
    }
    let winner: Team = score.teamA > score.teamB ? .teamA : .teamB
    gamesWon[winner, default: 0] += 1
    let gameRecord = GameRecord(
        gameNumber: index + 1,
        teamAFinalScore: score.teamA,
        teamBFinalScore: score.teamB,
        winningTeam: winner
    )
    // gameRecord.points and .completedAt both left at their defaults
    // (empty array, nil) — no point log and no per-game timing data
    // exist for a quick-logged game. Leaving completedAt nil is what
    // makes MatchDetailView's longestGameID (from the Chemistry/Game
    // Duration spec) correctly return nil for every quick-logged match,
    // while closestGameID still works from the final scores alone.
    gameRecords.append(gameRecord)
}
guard let matchWinner = (
    gamesWon[.teamA, default: 0] >= matchFormat.gamesToWin ? Team.teamA :
    gamesWon[.teamB, default: 0] >= matchFormat.gamesToWin ? Team.teamB : nil
) else {
    throw MatchRepositoryError.matchNotOver
}
```

(`MatchFormat.gamesToWin` is the same property `PickleballMatch.isMatchOver` already uses — no new match-format logic, just read directly here since there's no `PickleballMatch` instance to ask.)

`MatchRepositoryError` gains one new case, `invalidGameScore`, alongside the existing `matchNotOver`.

## UI integration

`MatchSetupView` reuses its own existing private `resolvedPlayers`/`resolvedPlayer` functions (the "Two Mikes" disambiguation + upsert logic `startMatch()` already has) unchanged — Quick Log's save path resolves Team A/B players exactly the same way a live match's does, since it's the same struct and the same already-typed name fields.

**Team names must get the same blank-name fallback a live match already gets.** `startMatch()` doesn't apply "Team A"/"Team B" itself — that fallback lives on `PendingMatchSetup.resolvedTeamAName`/`resolvedTeamBName` (applied later, at `confirmFirstServe`), which Quick Log never goes through since it never creates a `PendingMatchSetup`. Quick Log's save path applies the identical rule directly: `combinedName(teamAPlayer1, teamAPlayer2).isEmpty ? "Team A" : combinedName(...)` (and the Team B equivalent) — same fallback, same wording, just invoked at Quick Log's own save point instead of at `confirmFirstServe`.

**Row state uses a fixed-size array of small `Identifiable` structs, not a dynamically-resized array of tuples.** Tuples aren't `Identifiable`, which would force `ForEach(array.indices, id: \.self)` with index-based bindings (`$array[index].field`) — and mutating an array's *length* while a `TextField` is actively bound to one of its indices is a well-known source of index-out-of-bounds crashes and lost `@FocusState` focus in SwiftUI. It also doesn't fit the "never destroy typed-but-hidden text" requirement above: a dynamically-resized array has nothing else *to* keep the text in once a row is removed.

```swift
private struct QuickLogGameEntry: Identifiable, Equatable {
    let id: Int  // 1-based game number — stable for the life of the sheet
    var teamAText: String = ""
    var teamBText: String = ""
}
```

New local state on `MatchSetupView`:

```swift
@State private var isShowingQuickLog = false
@State private var quickLogEntries: [QuickLogGameEntry] = []
```

`quickLogEntries` is populated once, when the sheet is presented — `(1...((matchFormat.gamesToWin * 2) - 1)).map { QuickLogGameEntry(id: $0) }` — and never resized afterward; only its elements' `teamAText`/`teamBText` ever change, via normal `Binding` into the array by index (safe here specifically because the array's *length* never changes after creation — only element mutation, which SwiftUI/`@State` handles the same way it does for any other bound array of a fixed shape). A row's committed scores are derived separately (on each field's `onSubmit`, per "What it does" above), as `[(teamA: Int, teamB: Int)]`, by parsing each entry's text — this committed list, not `quickLogEntries` itself, is what both the "visible row count" computation and the eventual `saveQuickLoggedMatch` call consume. The sheet reads `playMode`, `matchFormat`, `winningScore`, `winByTwo` directly from `MatchSetupView`'s existing `@State` — Quick Log doesn't need its own copies of match-rules state, since it's presented from the same screen that already collected them. `scoringFormatKind`/`rallyFreeze`/`trackTimeouts` are still read (a `GameConfiguration` needs a `scoringFormat` and `timeoutsPerTeam` to round-trip through `configurationData` the same as any other match, even though neither is meaningfully exercised by an after-the-fact score entry) — no new fields, just reusing what's already on screen.

**`MatchDetailView`'s `gameCard(_:)` needs a small adjustment for an empty point log.** It currently renders the score header, a `Divider()`, then the point-by-point list unconditionally. For a quick-logged game (`game.orderedPoints.isEmpty`), that divider and the list's spacing would render with nothing underneath — the divider and point-list section should only appear `if !game.orderedPoints.isEmpty`.

## Testing

- `PickleballKitTests`: existing `PickleballGame.gameWinner` tests re-run unchanged (regression guard for the parts of the extraction that are behavior-preserving). New direct tests on `GameConfiguration.isCompletedGameScore` covering: below winning score, tied, win-by-2 violation, exact winning score, win-by-2 satisfied with extra margin (e.g. 11-0), exact overtime margin of 2 (e.g. 15-13), an impossible overtime margin (e.g. 15-10 — must be rejected), negative scores (must be rejected), and `.rally(freeze: true)` with a large overtime margin (must be *accepted*, since freeze's margin is deliberately unconstrained). A new `PickleballMatch`/`PickleballGame` test correcting a live score to an impossible overtime margin via `correctScore`, confirming it's now correctly rejected (not silently accepted as a win) — the regression test for the behavior change called out above.
- `MatchRepositoryTests`: new cases for `saveQuickLoggedMatch` — a Best of 1 single-game save; a Best of 3 where the match ends 2-0 (only two `GameRecord`s created, not three); an attempt to save a trailing game entry after the match was already decided (`invalidGameScore` thrown); an attempt to save with an incomplete/invalid final game score (`invalidGameScore` thrown); an attempt to save before any team has reached `matchFormat.gamesToWin` (`matchNotOver` thrown); confirms every saved `GameRecord.points` is empty and `.completedAt` is nil.
- A `MatchSetupView` UI test (matching existing `HistoryFilterUITests`-style conventions) driving the full Quick Log sheet for a Best of 1 match end to end, confirming: the saved match appears correctly in History with the entered score and no point-by-point log in `MatchDetailView`; the duration badge doesn't appear for it; blank team names fall back to "Team A"/"Team B"; and the button is gated behind `canStartNewMatch` the same way "Start Match" already is (a free user past `demoMatchLimit` sees the paywall, not the Quick Log sheet).

## Non-goals

- No validation of the `.rally(freeze: true)` "won while serving" rule, and no upper bound on that format's overtime margin — both documented above as the same known, narrow gap inherent to after-the-fact entry with no serve history, not an oversight.
- No "when did you actually play this?" date/time entry — both timestamps default to the moment of saving (see Timestamps above).
- No editing of an already-logged match's scores after the fact — same as live-played matches today, which also have no post-save score editing path.
