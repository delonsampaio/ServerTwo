# Doubles Court-Position (L/R) Tracking Design

**Goal:** During live doubles scoring, show which partner is currently positioned on the right (even) court vs. left (odd) court — the single most common mid-game question in recreational doubles ("wait, am I supposed to be on the left or right right now?").

## Context

Third of four specs from a feature-backlog review. Before designing anything, the exact pickleball rule was verified against external sources (not assumed) — see "The rule" below, with sources. Two scope decisions came out of that research and were confirmed with the user directly:

- **Side-out scoring only.** The official positioning rule is built around side-out's fixed-server-across-multiple-points model. Rally scoring has serve changing on every point regardless of score, so applying the same formula there wouldn't be "the rule," just a mechanical reuse of it where it doesn't actually apply. Rally-scored matches show no position badges.
- **Starting side is a stated assumption with a 1-tap escape hatch.** The app has no existing way to know which physical side two partners actually started on. Default: "Player 1" (as typed in Setup) starts on the right each game. A tap on either badge flips that team's assumption for the rest of the current game, resetting at the next game.

This is the simplest of the four specs architecturally — it turns out to need **zero changes to PickleballKit**. No new engine state, no new `GameConfiguration`/`GameRecord` fields, nothing persisted to SwiftData. Entirely a derived computation plus two pieces of live, non-persisted UI state in `ActiveMatchController`.

## The rule

Verified via two separate web searches against multiple independent sources (not assumed from memory) — the second specifically to resolve a question the first round of external review raised about whether this rule is doubles-specific or singles-only. It is not singles-only; both searches, independently, describe it as the general rule for the serving team regardless of mode:

- The server serves from the right court when their **team's own score** is even, left when odd — stated as "the team's score decides the position of its first server," not qualified to singles. The receiver's position is wherever they already are — matched diagonally to the server, not computed from the receiving team's own score.
- "Server 1" is a *positional*, not identity-based, label: whoever is standing on the right when a service turn begins is Server 1; the partner on the left is Server 2. It isn't "whichever player happened to start the game's first turn," re-applied for the rest of the match.
- Partners switch sides only when **their team scores while serving**; a lost rally changes nothing about positions. The receiving side never switches.
- When serve passes from Server 1 to Server 2 within the same team (not a full side-out), **neither partner moves** — Server 2 simply serves from wherever they're already standing, which is already correct for the score since nothing changed.
- The one documented exception: at the start of each game, only the starting server serves before the first side-out — the partner doesn't get a first turn. (`PickleballGame`'s existing `startingServerNumber: ServerNumber = configuration.playMode == .doubles ? .two : .one` already encodes exactly this — a strong signal the engine's serve-sequence logic is already correct and trustworthy as a foundation.)

Sources: [USA Pickleball — Pickleball Scoring & Positioning](https://usapickleball.org/?p=17818), [PlayPickleball — Pickleball Player Positions](https://playpickleball.com/pickleball-player-positions), [PickleProShop — Complete Guide to Pickleball Serving Rules](https://pickleproshop.com/blogs/articles/pickleball-serving-rules), [Warwick — Team Pickleball Rules](https://warwick.ac.uk/services/sport/active/leagues/team-pickleball-rules/), [The Dink — Pickleball Scoring Rules](https://www.thedinkpickleball.com/pickleball-scoring-rules-complete-guide-2026/), [BestPicklePad — Pickleball Scoring Guide](https://bestpicklepad.com/pickleball-scoring-guide). Sources differ slightly in wording but agree on every mechanic above.

**The key derivation this design relies on, verified by hand-tracing multiple sequences, not just asserted:** in side-out scoring, a team's score only ever increases while *they* are serving (verified directly against `PickleballGame.recordSideOutPoint` — the branch where the scoring team is *not* the server never calls `addScore`), and a swap happens exactly once per such point. This means a team's total swap count is, by construction, always exactly equal to their current score — there is no sequence of play where "frozen position from the last swap" and "current score parity" can disagree, because they are the same fact expressed two ways, not two independently-tracked quantities that happen to usually agree. **"Which player is currently on the right" is therefore fully derivable from `(team's own current score) % 2`** plus a starting-side assumption — no replay of point history needed, no new engine state. This holds for both the serving team and the receiving team (whose score, and therefore position, is simply frozen at whatever it was the last time they stopped serving) — including at the exact moment a team *regains* serve via a side-out, which a specific hand-traced sequence confirmed directly: a team frozen at an odd score, upon regaining serve, has its "Player 1" correctly sitting on the left, matching "odd → left" — not on the right as an earlier draft of this review incorrectly claimed.

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

These two are the *only* reset points needed. `stageMatch` (called when "Start Match" is tapped in Setup, before the coin flip) only creates a `PendingMatchSetup` — no live `PickleballMatch` exists yet at that point, and these two booleans default to `false` regardless, so there's nothing there to reset.

## Computing positions

A pure, private computation inside `ScoringView` — deliberately not in `PickleballKit`, since it needs player names, which the engine has no concept of:

```swift
private enum PlayerSlot {
    case right, left
    var badge: String { self == .right ? "R" : "L" }
}

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

/// Rows are fixed by *player* (Player 1's row never moves), with the
/// badge next to each name toggling between R/L as they swap sides —
/// not the other way around (rows fixed by court side, names jumping
/// between rows every time someone scores). Reading "find my own name,
/// check the letter next to it" is a much lower-friction glance mid-rally
/// than "remember whether I'm currently the top or bottom row."
private struct PartnerPositions: Equatable {
    let player1Name: String
    let player1Slot: PlayerSlot
    let player2Name: String
    let player2Slot: PlayerSlot  // always the opposite of player1Slot
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
        player1Name: player1,
        player1Slot: player1OnRight ? .right : .left,
        player2Name: player2,
        player2Slot: player1OnRight ? .left : .right
    )
}
```

(`guard case .sideOut = ...` — not `== .sideOut` — since `ScoringFormat` is an enum with an associated value on its other case, matching convention already used elsewhere in this codebase, e.g. `if case .rally(let freeze) = configuration.scoringFormat`.)

**Highlighting the active server is not simply "the right-side player."** An earlier draft of this design assumed the server is always on the right while their team is serving — wrong: once the server wins a point and the team's score becomes odd, they swap to the *left* and continue serving from there. The active server's side is a direct, independent parity check — `scoreIsEven ? .right : .left` — not an assumption piggybacked on `isServing` and "right." Still zero new engine state: both the position formula and the active-server side come from the same already-exposed score.

```swift
private func activeServerSide(score: Int) -> PlayerSlot {
    score % 2 == 0 ? .right : .left
}
```

## UI integration

**The flip badges cannot live inside `scoreZone`'s existing `Button`.** `scoreZone` (`ServerTwo/Scoring/ScoringView.swift:241-300`) is already one big `Button { recordPoint }` wrapping its entire card as the label. A nested `Button` inside another `Button`'s `label:` closure is a real, known SwiftUI/XCUITest trap, not a theoretical one: SwiftUI's accessibility tree collapses a `Button`'s label into one atomic element, so an inner `Button` is invisible to `app.buttons["..."]` in XCUITest — and the usual workaround (`.accessibilityElement(children: .contain)` on the outer button) breaks the *outer* button's own identification (`scoreZone.teamA` stops being a `.button` and every existing UI test that taps it breaks). This codebase has already hit this exact category of bug once — `ManagePlayersView`'s Rename/Set-as-Me buttons needed restructuring specifically because two interactive controls sharing one row stole each other's taps (see that file's own comments) — and solved it the same way this needs to be solved: **the flip control is a sibling layered on top via `ZStack`, never a child inside the scoring button's label.**

```swift
private func scoreZone(for team: Team, match: PickleballMatch) -> some View {
    let name = team == .teamA ? activeMatchController.teamAName : activeMatchController.teamBName
    let score = match.currentGame.state.score(for: team)
    let isServing = match.currentGame.state.servingTeam == team
    let positions = partnerPositions(for: team, match: match)

    return ZStack {
        // Unchanged: the whole card is still one Button, tap-to-score.
        // Its name slot becomes an empty reservation (Color.clear, sized
        // to match the two-row partner display) when positions != nil,
        // so the big score number and "Tap to Score" don't shift — the
        // real name/badges render as a sibling on top, not nested here.
        Button {
            activeMatchController.recordPoint(for: team)
        } label: {
            VStack(spacing: 8) {
                servingBadgeSlot  // unchanged
                Spacer()
                if positions == nil {
                    Text(name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Color.clear.frame(height: partnerRowsHeight)
                }
                Text("\(score)")
                    .font(.system(size: 108, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Tap to Score")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(/* unchanged */)
            .overlay(/* unchanged */)
        }
        .buttonStyle(.plain)

        // Sibling, not child — SwiftUI hit-tests this independently of
        // the Button beneath it. Positioned to land exactly where the
        // Color.clear reservation above sits; exact offset/alignment
        // needs visual verification during implementation, not just
        // this sketch.
        if let positions {
            VStack(spacing: 2) {
                partnerRow(positions.player1Name, slot: positions.player1Slot, isActiveServer: isServing && positions.player1Slot == activeServerSide(score: score), team: team)
                partnerRow(positions.player2Name, slot: positions.player2Slot, isActiveServer: isServing && positions.player2Slot == activeServerSide(score: score), team: team)
            }
            .padding(.top, /* aligned to the reserved slot */)
        }
    }
}

private func partnerRow(_ name: String, slot: PlayerSlot, isActiveServer: Bool, team: Team) -> some View {
    HStack(spacing: 6) {
        Button {
            activeMatchController.toggleStartingSideOverride(for: team)
        } label: {
            Text(slot.badge)
                .font(.caption2.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.1), in: Circle())
        }
        .accessibilityIdentifier("PositionBadge.\(team == .teamA ? "teamA" : "teamB").\(slot.badge)")
        Text(name)
            .font(.subheadline.weight(isActiveServer ? .bold : .medium))
            .foregroundStyle(isActiveServer ? .primary : .secondary)
            .lineLimit(1)
    }
}
```

Falls back to today's unchanged single-line name for singles and rally-scored matches (`partnerPositions` returns `nil` for both; the `if positions == nil` branch renders identically to current behavior, nothing changes for those matches).

**Blank doubles names are an accepted edge case, not fixed here.** If a user starts a doubles match with both name fields empty, `MatchSetupView.combinedName` produces an empty string, and `PendingMatchSetup.resolvedTeamAName`'s existing fallback turns that into the single string `"Team A"` (no `" & "` separator) — so `doublesPartnerNames` correctly returns `nil`, and the match simply shows today's unchanged single-line "Team A" display, no position badges. Deliberately not fixing this by changing what `resolvedTeamAName` falls back to for doubles: that fallback is shared with `CoinFlipView` and other call sites outside this feature, and changing it to produce two splittable names (e.g. "Player 1 & Player 2") would ripple into those screens as a side effect of a feature those screens have nothing to do with. Starting a real doubles match with zero names typed is already a degenerate case; falling back to today's existing display is acceptable.

## Testing

- A `ScoringView` or `ActiveMatchController`-level unit test driving a doubles side-out match through several points, confirming: starting positions (Player 1 right, Player 2 left); positions swap after the serving team scores; positions stay frozen for the receiving team; positions stay unchanged when serve passes Server 1 → Server 2 within a team (no full side-out); a team *regaining* serve via a side-out at an odd frozen score correctly has its right-side player matching the left/odd convention (the specific scenario the external review's rejected counterexample got wrong — worth a named regression test precisely because it's the one case that looked, on first analysis, like it might not hold); the active-server highlight correctly follows the score-parity side even after the server has swapped mid-turn (Bug A's regression test); the override flip inverts the assumption for the rest of that game; the override resets at the start of the next game (including via a match-deciding point) and after an undo that crosses a game boundary.
- Confirms `partnerPositions` returns `nil` (no change from current single-line display) for: singles matches, rally-scored matches (either freeze setting), and a doubles team name with no " & " separator (the blank-names edge case).
- A UI test tapping `PositionBadge.teamA.R` (or whichever badge is currently showing) and confirming via assertion — not just a screenshot — that: the override toggled, and `activeMatchController`'s score for that team did *not* change. This is the one finding most needing empirical verification: confirming the sibling-ZStack structure actually routes the tap to the badge and not to `scoreZone.teamA`'s own Button underneath it.

## Non-goals

- No support for "stacking" (a real, legal advanced doubles strategy where partners voluntarily position off the textbook diagonal slots after the serve) — this models the standard, non-stacking position only. Flagged, not silently ignored: a team using stacking will see badges that don't match their actual on-court positions. Casual/recreational play (this app's stated audience) overwhelmingly doesn't stack; this is an accepted limitation, not an oversight.
- No position tracking for rally-scored or singles matches — see Context above.
- No persistence of the override flip, or of position history, to `GameRecord`/`MatchRecord` — purely live display state, gone once the match ends, same as `correctingTeam` or `focusedField`.
