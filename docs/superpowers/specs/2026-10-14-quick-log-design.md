# Post-Match Quick Log Design

**Goal:** Let a player record a match that already happened — phone was in their bag during play — by entering each game's final score directly, instead of the only option today (live, point-by-point tapping through `ScoringView`).

## Context

Second of four specs from a feature-backlog review (first was Chemistry Stats & Game Duration). Two things distinguish this one from the first: it needs **zero schema changes** (`GameRecord.points` already defaults to empty — no new field required), but it **does** touch the live scoring engine, unlike the first — specifically, it extracts an existing validation rule out of `PickleballGame` so Quick Log can reuse it rather than duplicate it. That extraction is flagged explicitly below since engine code deserves more scrutiny than a UI-only addition.

## What it does

`MatchSetupView` gains a secondary action — "Log Final Score Instead" — next to the primary "Start Match" CTA. It's visually secondary (a text button, not competing with the pinned CTA), the same relationship "Already spun a paddle?" has to the main flow on `CoinFlipView`.

Tapping it opens a sheet (matching the established sheet-over-alert pattern already used for Rename/Add Player — `.alert` with embedded input is the one pattern this codebase has already found unreliable in XCUITest). The sheet shows:

- The already-entered Team A / Team B names, read-only.
- One row per game, each with two number-pad text fields (Team A score, Team B score). Scores run into the teens (13-11, 15-13, 21-19 are all legal depending on configuration), so a `Stepper` would take too many taps — a numeric keyboard is the right input for "quick."
- A new row only appears once the previous one holds a **valid, completed** game score (validated against the match's configured win condition — see below). This mirrors how live play naturally stops prompting for more games once the match is decided: once a team reaches `matchFormat.gamesToWin`, no further row appears. An incomplete or invalid entry (scores not yet reaching the target, a tie, or a 1-point margin under Win by 2) simply doesn't advance — no new row, no intrusive error alert, "Save" just stays disabled. This is read the same way the rest of the app treats in-progress input: nothing to correct, just nothing to do yet.
- Editing an earlier row's score after later rows already appeared re-validates from that row forward: if the edit makes that game no longer a valid completed score, or changes which team won it, every row after it is removed (the match may no longer be decided at that point, or may now be decided after fewer games than before) — the row list is always a direct function of the scores entered so far, never stale state left over from a previous edit.
- "Save" is disabled until at least one valid game exists and the match is actually decided (someone has reached `matchFormat.gamesToWin`) — a half-entered match can't be saved as "complete" history, the same constraint live play already enforces via `MatchRepositoryError.matchNotOver`.

On save, this bypasses `PickleballMatch`/`ActiveMatchController` entirely and writes straight to SwiftData via a new, dedicated repository method (see below) — there is no live match to drive, and no point-by-point log to produce (`GameRecord.points` stays empty for every game, exactly like the original backlog framing: "no point-by-point log").

### Timestamps

Both `startedAt` and `completedAt` default to `Date()` at the moment of saving. The match genuinely happened earlier, but there's no live timing data to recover, and asking "when did you actually play?" adds a required field to the one screen explicitly meant to minimize friction. The known, accepted side effect: a quick-logged match's duration badge (from the Chemistry/Game Duration spec) will read "< 1 min" rather than reflecting the real game. That's an honest reflection of "we don't know," not a bug to design around.

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

The first three checks (score reached, not tied, win-by-2 if configured) are pure functions of the two final scores and the configuration — exactly what Quick Log needs. The last check (`.rally(freeze: true)`'s "won while serving" rule) depends on live serve-sequence state that doesn't exist for an after-the-fact score entry — there's no point history to know who served last. Quick Log can't evaluate that condition and doesn't try to; a `.rally(freeze: true)` match quick-logged with a legal final score is accepted even though the live engine might have additionally required the winning point to be a serve-won point. This is a known, narrow gap, not an oversight — documented in Non-goals below.

**Extracted into `GameConfiguration`** (`PickleballKit/Sources/PickleballKit/GameConfiguration.swift`), so both call sites share one source of truth instead of two copies of the same rule drifting apart:

```swift
/// Whether `scoreA`/`scoreB` represents a completed game under this
/// configuration's win condition (score reached, not tied, win-by-2 if
/// required). Deliberately does NOT evaluate `.rally(freeze: true)`'s
/// "won on serve" rule — that depends on live serve-sequence state this
/// pure score check has no access to. `PickleballGame.gameWinner` layers
/// that check on top for live play; this is for validating an
/// already-known final score with no serve history (e.g. Quick Log).
public func isCompletedGameScore(teamA: Int, teamB: Int) -> Bool {
    guard max(teamA, teamB) >= winningScore.rawValue, teamA != teamB else { return false }
    if winByTwo && abs(teamA - teamB) < 2 { return false }
    return true
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

This is a pure extract-and-call refactor — every existing input to `gameWinner` produces the identical output. `PickleballKitTests` already has coverage for `gameWinner` across win-by-2, exact-score, and rally-freeze cases; those tests are the regression guard for this refactor and need no changes themselves, just a passing re-run.

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
    // gameRecord.points left at its default (empty) — no point log exists.
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

New local state: `@State private var isShowingQuickLog = false` and `@State private var quickLogGameScores: [(teamAText: String, teamBText: String)] = [("", "")]` (always at least one row; a new blank row is appended whenever the last row's entry becomes a valid completed-game score and the match isn't yet decided). The sheet reads `playMode`, `matchFormat`, `winningScore`, `winByTwo` directly from `MatchSetupView`'s existing `@State` — Quick Log doesn't need its own copies of match-rules state, since it's presented from the same screen that already collected them. `scoringFormatKind`/`rallyFreeze`/`trackTimeouts` are still read (a `GameConfiguration` needs a `scoringFormat` and `timeoutsPerTeam` to round-trip through `configurationData` the same as any other match, even though neither is meaningfully exercised by an after-the-fact score entry) — no new fields, just reusing what's already on screen.

## Testing

- `PickleballKitTests`: existing `PickleballGame.gameWinner` tests re-run unchanged (regression guard for the extract refactor). New direct tests on `GameConfiguration.isCompletedGameScore` covering: below winning score, tied, win-by-2 violation, exact winning score, win-by-2 satisfied.
- `MatchRepositoryTests`: new cases for `saveQuickLoggedMatch` — a Best of 1 single-game save; a Best of 3 where the match ends 2-0 (only two `GameRecord`s created, not three); an attempt to save with an incomplete/invalid final game score (`invalidGameScore` thrown); an attempt to save before any team has reached `matchFormat.gamesToWin` (`matchNotOver` thrown); confirms every saved `GameRecord.points` is empty.
- A `MatchSetupView` UI test (matching existing `HistoryFilterUITests`-style conventions) driving the full Quick Log sheet for a Best of 1 match end to end, confirming the saved match appears correctly in History with the entered score and no point-by-point log in `MatchDetailView`.

## Non-goals

- No validation of the `.rally(freeze: true)` "won while serving" rule — documented above as a known, narrow gap inherent to after-the-fact entry with no serve history, not an oversight.
- No "when did you actually play this?" date/time entry — both timestamps default to the moment of saving (see Timestamps above).
- No editing of an already-logged match's scores after the fact — same as live-played matches today, which also have no post-save score editing path.
