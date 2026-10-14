# Doubles Court-Position (L/R) Tracking Design

**Goal:** During live doubles scoring, show which partner is currently positioned on the right (even) court vs. left (odd) court — the single most common mid-game question in recreational doubles ("wait, am I supposed to be on the left or right right now?").

## Context

Third of four specs from a feature-backlog review. Before designing anything, the exact pickleball rule was verified against external sources (not assumed) — see "The rule" below, with sources. Two scope decisions came out of that research and were confirmed with the user directly:

- **Side-out scoring only.** The official positioning rule is built around side-out's fixed-server-across-multiple-points model. Rally scoring has serve changing on every point regardless of score, so applying the same formula there wouldn't be "the rule," just a mechanical reuse of it where it doesn't actually apply. Rally-scored matches show no position badges.
- **Starting side is a stated assumption with a 1-tap escape hatch.** The app has no existing way to know which physical side two partners actually started on. Default: "Player 1" (as typed in Setup) starts on the right each game. A tap on either badge flips that team's assumption for the rest of the current game, resetting at the next game.

This is the simplest of the four specs architecturally — it turns out to need **zero changes to PickleballKit**. No new engine state, no new `GameConfiguration`/`GameRecord` fields, nothing persisted to SwiftData. Entirely a derived computation plus two pieces of live, non-persisted UI state in `ActiveMatchController`.

## The rule

Verified via web search against USA Pickleball guidance and multiple independent sources (not assumed from memory):

- The server serves from the right court when their **team's own score** is even, left when odd. The receiver's position is wherever they already are — matched diagonally to the server, not computed from the receiving team's own score.
- Partners switch sides only when **their team scores while serving**. The receiving side never switches.
- When serve passes from Server 1 to Server 2 within the same team (not a full side-out), **neither partner moves** — Server 2 simply serves from wherever they're already standing, which is already correct for the score since nothing changed.
- The one documented exception: at the start of each game, only the starting server serves before the first side-out — the partner doesn't get a first turn. (`PickleballGame`'s existing `startingServerNumber: ServerNumber = configuration.playMode == .doubles ? .two : .one` already encodes exactly this — a strong signal the engine's serve-sequence logic is already correct and trustworthy as a foundation.)

Sources: [USA Pickleball — Pickleball Scoring & Positioning](https://usapickleball.org/?p=17818), [PlayPickleball — Pickleball Player Positions](https://playpickleball.com/pickleball-player-positions), [PickleProShop — Complete Guide to Pickleball Serving Rules](https://pickleproshop.com/blogs/articles/pickleball-serving-rules). Sources differ slightly in wording but agree on the core mechanics above.

**The key derivation this design relies on:** in side-out scoring specifically, a team's score only ever increases while *they* are serving (verified directly against `PickleballGame.recordSideOutPoint` — the branch where the scoring team is *not* the server never calls `addScore`). Since a team's position-swap count and their own score-increment count are therefore the same number, **"which player is currently on the right" is fully derivable from `(team's own current score) % 2`** plus a starting-side assumption — no replay of point history needed, no new engine state. This is true for both the serving team (actively proven by the rule) and the receiving team (their score, and therefore their position, is simply frozen at whatever it was the last time they stopped serving).

Note this is unrelated to the existing "Switch Sides" feature (`hasSideSwitched`, already shipped) — that swaps which *end of the court* the two teams occupy relative to each other; this feature tracks each team's *own two players'* left/right assignment within their own side. Independent concepts, no interaction between them.

## Live state

Two new non-persisted properties on `ActiveMatchController` — this is UI/session state, never written to `GameRecord`/`MatchRecord`, so it doesn't need the undo-safe array treatment the Chemistry/Game Duration spec's `gameCompletionDates` needed (that tracked real data being saved to history; this is a display convenience discarded the moment the match ends):

```swift
private(set) var teamADidSwapStartingSides = false
private(set) var teamBDidSwapStartingSides = false

func toggleStartingSideOverride(for team: Team) {
    switch team {
    case .teamA: teamADidSwapStartingSides.toggle()
    case .teamB: teamBDidSwapStartingSides.toggle()
    }
}
```

Both reset to `false` whenever the current game index changes, in *either* direction — a completed-game-triggered advance to a new game, or an undo back into a previous one. Reusing the same "did `completedGames.count` change" check the Quick Log spec's `syncGameCompletionDates` already established for `recordPoint`/`undo`/`correctScore`, just a reset instead of an array resize (there's no historical data to preserve here — if a user undoes back into a previous game, re-tapping the flip for that game, should they need it, is a trivial cost for state that was never going to be remembered anyway).

**Also reset at `confirmFirstServe` and `resumeIfNeeded`, not just inside the three wrapper methods.** `ActiveMatchController` is a single long-lived instance reused across many matches over an app session, not recreated per match — without an explicit reset at the two places a match actually *begins* (a fresh one via `confirmFirstServe`, or a crash-recovered one via `resumeIfNeeded`), a flip left set from a *previous* match would silently leak into the next one's starting assumption. A crash-resumed match simply starts both back at `false` (losing whatever flip was set before the crash) — acceptable for the same reason undoing across a game boundary is: this is cosmetic, non-persisted state, never meant to survive past the moment it's useful.

## Computing positions

A pure, private computation inside `ScoringView` — deliberately not in `PickleballKit`, since it needs player names, which the engine has no concept of:

```swift
/// `teamName` is the already-resolved combined display name (e.g.
/// "Delon & Katie", from `ActiveMatchController.teamAName`/`teamBName`)
/// — split on " & " to recover the two individually-typed names, the
/// same convention `MatchRepository.mySide`'s legacy name-fallback
/// already relies on. `nil` for singles (nothing to split) or any name
/// that doesn't contain the separator — an accepted, pre-existing
/// limitation shared with that fallback, not a new one.
private func doublesPartnerNames(_ teamName: String) -> (player1: String, player2: String)? {
    let parts = teamName.components(separatedBy: " & ")
    guard parts.count == 2 else { return nil }
    return (parts[0], parts[1])
}

private struct PartnerPositions: Equatable {
    let rightName: String
    let leftName: String
}

private func partnerPositions(for team: Team, match: PickleballMatch) -> PartnerPositions? {
    guard case .sideOut = match.configuration.scoringFormat else { return nil }
    let teamName = team == .teamA ? activeMatchController.teamAName : activeMatchController.teamBName
    guard let (player1, player2) = doublesPartnerNames(teamName) else { return nil }
    let didSwap = team == .teamA
        ? activeMatchController.teamADidSwapStartingSides
        : activeMatchController.teamBDidSwapStartingSides
    let score = match.currentGame.state.score(for: team)
    // Player 1 starts right unless overridden; see "The key derivation"
    // above for why (score % 2) alone tells us whether that's still true.
    let player1OnRight = (score % 2 == 0) != didSwap
    return PartnerPositions(
        rightName: player1OnRight ? player1 : player2,
        leftName: player1OnRight ? player2 : player1
    )
}
```

(`guard case .sideOut = ...` — not `== .sideOut` — since `ScoringFormat` is an enum with an associated value on its other case, matching convention already used elsewhere in this codebase, e.g. `if case .rally(let freeze) = configuration.scoringFormat`.)

Because the right-side player is, by the rule itself, always whoever is currently in the serving slot *when their team is serving*, no separate "who is Server 1 vs Server 2" resolution is needed for display — `scoreZone`'s existing `isServing` boolean, combined with "right side," is sufficient to also highlight which specific partner is the active server.

## UI integration

`ScoringView.scoreZone(for:match:)` currently renders a single `Text(name)` line for the team's combined name (`ServerTwo/Scoring/ScoringView.swift:273-277`). This becomes conditional:

```swift
if let positions = partnerPositions(for: team, match: match) {
    VStack(alignment: .leading, spacing: 4) {
        partnerRow(positions.rightName, badge: "R", isActiveServer: isServing, team: team)
        partnerRow(positions.leftName, badge: "L", isActiveServer: false, team: team)
    }
} else {
    Text(name)
        .font(.title.weight(.bold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
}
```

— falling back to today's unchanged single-line name for singles and rally-scored matches (`partnerPositions` returns `nil` for both, so the `else` branch is reached identically to current behavior; nothing changes for those matches).

Each `partnerRow` pairs the player's name with a small tappable L/R badge — tapping it calls `activeMatchController.toggleStartingSideOverride(for: team)`. **This needs explicit verification during implementation, not just assumption:** the badge is a `Button` nested inside `scoreZone`'s own outer `Button` (the whole card is already tappable to record a point). SwiftUI generally lets a nested interactive control intercept its own taps before the outer `Button` does, but this codebase has hit real nested-tap-target bugs before (`ManagePlayersView`'s Rename/Set-as-Me buttons needed explicit `.buttonStyle(.bordered)` specifically to stop two sibling buttons from stealing each other's taps) — so this needs an actual on-device/simulator tap test confirming the flip badge never also records a point, not just a visual screenshot.

## Testing

- A `ScoringView` or `ActiveMatchController`-level unit test driving a doubles side-out match through several points, confirming: starting positions (Player 1 right, Player 2 left); positions swap after the serving team scores; positions stay frozen for the receiving team; positions stay unchanged when serve passes Server 1 → Server 2 within a team (no full side-out); the override flip inverts the assumption for the rest of that game; the override resets at the start of the next game (including via a match-deciding point) and after an undo that crosses a game boundary.
- Confirms `partnerPositions` returns `nil` (no change from current single-line display) for: singles matches, rally-scored matches (either freeze setting), and a doubles team name with no " & " separator.
- A UI test specifically confirming that tapping a position badge toggles the override *without* also recording a point for that team (the nested-button risk called out above) — this is the one finding from this spec that most needs empirical, not just logical, verification.

## Non-goals

- No support for "stacking" (a real, legal advanced doubles strategy where partners voluntarily position off the textbook diagonal slots after the serve) — this models the standard, non-stacking position only. Flagged, not silently ignored: a team using stacking will see badges that don't match their actual on-court positions. Casual/recreational play (this app's stated audience) overwhelmingly doesn't stack; this is an accepted limitation, not an oversight.
- No position tracking for rally-scored or singles matches — see Context above.
- No persistence of the override flip, or of position history, to `GameRecord`/`MatchRecord` — purely live display state, gone once the match ends, same as `correctingTeam` or `focusedField`.
