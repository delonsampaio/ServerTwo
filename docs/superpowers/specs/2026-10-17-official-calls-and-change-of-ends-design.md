# Official Calls and Change of Ends Design

**Date:** 2026-10-17
**Status:** Draft for review (Gemini review, then user review, before a plan is written). Rule text verified against the official 2026 USA Pickleball Official Rulebook PDF supplied by the user (see "Verified rule text").
**Builds on:** `docs/superpowers/specs/2026-10-16-voice-announcer-design.md` (the announcer as built)

## Goal

Two related changes found while asking "what is the official way to announce a score":

1. **Make the announcer sound more like a real referee**: add "Side out.", "Game point." / "Match point.", and the official-style game/match endings.
2. **Follow the official change-of-ends rule.** Today the app prompts "Switch Sides" (and now speaks "Switch sides.") at the midpoint of EVERY game. The rule says teams change ends after every completed game, and change ends mid-game only at the midpoint of the LAST game of the match format.

The user delegated the choices to the controller ("for 1 and 2 do what is best"); the user declined the separate "best installed voice" idea. This spec records what was chosen and why.

## Verified rule text

From the official **2026 USA Pickleball Official Rulebook** PDF (the user supplied it; text extracted locally). The earlier Gemini answers and a third-party reproduction used different rule numbers; ONLY the numbers below, taken from the PDF, are to be cited anywhere in this project.

- **Calling the score, Rule 6.B:** the server normally calls the score. 6.B.1 singles: two numbers, server's score then receiver's, starting "zero – zero". 6.B.2 doubles: three numbers, serving team's score, receiving team's score, server number, starting "zero – zero – two". The entire score is called before the serve (Rule 6.C, "When to Serve").
- **Rally scoring, provisional Rule 14.A:** the score is called as two numbers, server's score then receiver's.
- **Referee calls, Rules 17.D.3 to 17.D.5** (the referee, during a match): "point" after each point; "second server" (or "second serve") after the first server's team loses a rally (doubles); "side out" when a singles player or the second server loses the serve. So "Side out" and "Second server" are official referee calls, not just conventions.
- **End Change Time-Out, Rule 21.B:** in a **single game or tie-breaker game** the players change ends when the first singles player or doubles team reaches 6 (game to 11), 8 (to 15), 11 (to 21). The rulebook elsewhere speaks of "the tie-breaker game of a multiple-game match", i.e. the deciding game (game 3 of a best of 3, game 5 of a best of 5). 21.B.4: after the change, play continues with the same server. 21.B.5: a maximum of one minute to change ends during a game.
- **Time-Out Between Games, Rule 21.F:** 21.F.1 a maximum of two minutes is allowed to change ends between games. **21.F.2: "Singles players or doubles teams must change ends and initial service for the next game of the match."** 21.F.3: teams may change the starting server between games.
- **"Game point" / "Match point"** are not rulebook calls (the only mention of "match point" is a remark that every point is equally important). They are a pro-tour broadcast convention, per Gemini, kept as an optional courtesy.
- **Out of scope, now verified:** 21.F.2 says initial service also changes with each game. The app gives the next game's first serve to the previous game's winner. See Open question 2.

## Decisions

1. **Add "Side out."** (Rule 17.D.5) before the new score call when possession changes. Side-out scoring only (rally scoring has no side-outs). Spoken only on a FORWARD move, never on undo or correction.
2. **Add "Game point." / "Match point."** after the score call. See "Game point rule" below.
3. **Add "Second server."** (Rule 17.D.4), doubles side-out only, before the call when the same team keeps the serve and the server number goes from 1 to 2, FORWARD move only. (An earlier draft skipped it as redundant with the trailing "2"; the official rulebook lists it as a referee call, and the point of this change is a more official sound.)
4. **Official-style endings:**
   - Best of 1: `"Game and match, <winner>, <winner score> to <loser score>."`
   - Best of 3/5 clincher: `"Game <N> to <winner>, <winner score> to <loser score>. Game and match, <winner>, <winner games> games to <loser games>."` The tally is spoken as "2 games to 1" (not "2 to 1") so it is not mistaken for a point score.
5. **Change of ends follows the rule:**
   - Mid-game "Switch Sides" / "Switch back" prompt and the spoken "Switch sides." / "Switch back." apply ONLY when the current game is the last game of the match format (best of 1: the only game; best of 3: game 3; best of 5: game 5).
   - After every completed game that does not end the match, the Game Over sheet says teams change ends, and the spoken game line says "Change ends." before "Next game, ...".
6. **No setting** to switch the old (every game) behaviour back (YAGNI). If casual players want it, it is a later toggle.
7. Engine unchanged except one read-only use of existing public API (`PickleballGame.history.count`) for the move count.

## Behaviour

### Spoken lines (planner output; every line a sentence ending in a period)

| Change (old → new) | Spoken |
|---|---|
| Serving team changed, scores unchanged, same game, side-out scoring, FORWARD move | `"Side out."`, then the score call |
| Same serving team, server number 1 → 2, scores unchanged, same game, doubles side-out, FORWARD move | `"Second server."`, then the score call |
| Same-game score/serve change where the serving team can win on the next point | the score call, then `"Game point."`; or `"Match point."` when winning would also win the match |
| Game completed, match continues | `"Game <N> to <winner>, <w> to <l>."`, `"Change ends."`, `"Next game, <call>."` |
| Match over, best of 1 | `"Game and match, <winner>, <w> to <l>."` |
| Match over, best of 3/5 | `"Game <N> to <winner>, <w> to <l>."`, `"Game and match, <winner>, <wg> games to <lg>."` |
| Flag false → true, current game is the last game of the format | the score call, then `"Switch sides."` |
| Flag true → false, current game is the last game of the format | the score call, then `"Switch back."` |
| Flag changes in any other game | the score call only (no switch line) |
| Everything else | unchanged from the announcer spec |

"Forward move" = the game's move count (`history.count`) rose. An undo lowers it. Timeouts and corrections also append to history, so they count as forward moves; a correction never changes the serving team, so it never triggers "Side out."

### Game point rule

A team "can win on the next point" when, after adding one to ITS score and leaving the other unchanged, (1) its new score is strictly greater than the opponent's AND (2) `configuration.isCompletedGameScore(teamA:teamB:)` is true for the resulting pair. **Condition (1) is required**: `isCompletedGameScore` is symmetric (it looks at `max`/`min`), so without it a trailing serving team would be reported at game point whenever the OTHER team already holds a winning-looking score. That state is reachable in `.rally(freeze: true)`, where a receiving team can reach or pass the target with a lead without the game ending until it wins a rally on serve (e.g. 13-10 with the 10-point team serving: 10+1 = 11, `isCompletedGameScore(13, 11)` is true, but the serving team is still losing).

Eligible teams:
- **Side-out scoring and rally freeze:** only the SERVING team can end the game on the next rally.
- **Rally without freeze:** either team can, so both are checked.

"Game point." is spoken when an eligible team can win on the next point. **"Match point." replaces it** when ANY eligible team that can win on the next point also has `gamesWon + 1 >= matchFormat.gamesToWin` (so a rally non-freeze 10-10, win-by-one board in a game that would clinch for one team and only win a game for the other is "Match point."). Best of 1: every game point is match point.

Stakes are evaluated and spoken ONLY when a score call is spoken for the change (inside the "call changed" branch), never on their own. So undoing a timeout on a game-point board stays silent, and a timeout itself speaks only "Timeout, <team>.".

### Composition order (one same-game change, at most these four slots, in this order)

1. Optional prefix, at most one, only when the move count rose AND the scores are unchanged AND scoring is side-out: `"Side out."` if the serving team changed, else `"Second server."` if (doubles) the serving team kept the serve and the server number went 1 → 2.
2. The score call (when the call changed): `"<call>."`
3. Optional switch line (only in the last game of the format): `"Switch sides."` (flag false → true) or `"Switch back."` (true → false).
4. Optional stakes line (only when the call changed): `"Match point."` or `"Game point."`.

Examples: side-out into game point: `["Side out.", "10, 8, 1.", "Game point."]`; second server on game point: `["Second server.", "10, 8, 2.", "Game point."]`; a correction from 0-0 to 10-8 in a deciding game: `["10, 8, 1.", "Switch sides.", "Game point."]` (the call's server number depends on the board).

### Change of ends in the UI

- `ScoringView`'s side-switch prompt logic (`syncSideSwitchPrompt` and the correction sheet's `onDismiss` re-check) only enqueues a side-switch prompt when the current game index equals `matchFormat.rawValue - 1` (the last game of the format). The per-game-index tracker, queue, stale-drop and resume seeding stay as built.
- The Game Over sheet gains a SEPARATE line "Teams change ends." above the existing line, which stays exactly "Next game starts at 0-0." (an existing UI test, `ScoringPromptsUITests`, asserts that exact text, so it must remain its own element).
- The engine's `hasSideSwitched` flag is unchanged; it simply is not acted on in non-last games.

### Resume and undo

- A resumed match behaves the same: nothing is spoken or prompted on appearance.
- Undo from the last game back into an earlier game (the game index falls) speaks the restored call, never a switch line.
- Undo from a later game back into an earlier game speaks the restored call, plus "Game point."/"Match point." when the restored board is one (no prefix, no switch line).

## Architecture

- `AnnouncementSnapshot` gains `moveCount: Int` (`match.currentGame.history.count`). `AnnouncementPlanner.plan` already receives `matchFormat` and `configuration`; it computes the last-game gate (`new.gameIndex == matchFormat.rawValue - 1`), game/match point, and the side-out line itself. No new parameters on `plan`.
- A tiny pure helper on `MatchFormat` (app target) names the gate once, so the planner and `ScoringView` share it: `isLastGame(index:)`.
- `ScoringPromptSheet`'s Game Over sheet adds the "Teams change ends." line; the new text is a testable static helper.
- No PickleballKit changes.

## Edge cases to handle

- Game point/match point in overtime (win by 2): 10-10 → no; 11-10 serving → yes; 12-11 → yes.
- Match point only when the game win would clinch the match; best of 1 every game point is match point.
- A correction landing on a game-point board speaks the call plus "Game point." (descriptive).
- An undo that restores the serving team does NOT say "Side out." (move count fell).
- The first game of a best of 3 reaching 6: no "Switch sides." and no prompt; game 3 reaching 6: both.
- Existing tests that will change or must be re-checked: `AnnouncementPlannerTests` lines asserting `"Delon wins, 11 to 5."` and `"Delon wins the match, 2 to 0."` (new endings); `ScoringPromptsUITests` asserts `staticTexts["Next game starts at 0-0."]` (kept as its own element) and dismisses "Switch Sides" (the implementer must confirm that flow uses the last game of its format, best of 1, otherwise the test must change to a deciding game); the score-correction UI test asserts the Side Switch sheet in the default format.
- Rally freeze serving-only vs non-freeze either-team (above).

## Testing

- Planner unit tests (exact strings): "Side out." forward in singles and doubles side-out; not on undo; not in rally; "Second server." forward only; game point for the serving team only (side-out), either team (rally non-freeze); not at 8-10 with the 10-point team receiving; overtime cases (10-10 no, 11-10 serving yes, 12-11 yes); match point and its precedence when both teams can win in non-freeze rally; the three ending wordings (winner first for Team B); "Change ends." line; switch lines gated by last game for best of 1/3/5; composition cases: side-out into game point `["Side out.", "10, 8, 1.", "Game point."]`, second server on game point, undoing a timeout on a game-point board is `[]`, rally-freeze 13-10 with the 10-point team serving has NO game point, a correction landing on game point.
- A pure test of `MatchFormat.isLastGame(index:)`.
- A test of the new Game Over caption helper.
- `ScoringView` gating covered by one UI test: a best-of-3 game 1 corrected to 6-0 shows NO Side Switch sheet (assert absence), while the existing best-of-1 test still shows it. Keep the UI test count low: extend an existing test where possible.
- Manual (user): best of 3, game 1 passing 6 → silent; game 3 passing 6 → "Switch sides."; game over between games says "Change ends."; "Side out." on a side-out and not after undo; "Game point." when serving at 10-8; "Match point." in a clincher.

## Out of scope

Initial-service alternation between games (Open question 2), "Point" before each score, "Fault", "Let", medical timeouts, a settings toggle for the old switching behaviour, an announcement or prompt for the 2-minute / 1-minute change-of-ends timers.

## Open questions with proposed defaults

1. ~~Verify the change-of-ends rule against the official rulebook~~ **Done** against the 2026 PDF (Rules 21.B and 21.F above).
2. **Initial service between games (Rule 21.F.2) is verified official, and the app deviates.** `PickleballMatch.recordPoint` creates the next game with `firstServingTeam: winner`. The rule says the initial service changes each game, so after the team that serves first in game 1, the OTHER team serves first in game 2, and the original team in game 3. Fixing it touches the engine and needs the match to remember who served first in game 1 (and persisted in-progress matches). Default: NOT part of this spec; recommend a separate small spec, because it changes persisted-match behaviour and many users play "winner serves".
3. **"Change ends." on every game break** even for players who do not follow the rule. Default: yes (Rule 21.F.2).
4. **Optional courtesy calls.** "Game point." / "Match point." are not rulebook calls. Default: keep (the user asked for a more official, informative announcer); serving team only in side-out.

## As built

- `AnnouncementSnapshot.moveCount` (`currentGame.history.count`) distinguishes forward moves from undo; `AnnouncementPlanner.plan` composes prefix, call, switch line and stakes in that order; `pointStakes` requires the team to be strictly ahead after the point (the score check is symmetric) and uses serving-team-only eligibility for side-out and rally freeze, either team for rally without freeze.
- `MatchFormat.isLastGame(index:)` gates both the spoken "Switch sides."/"Switch back." and `ScoringView.syncSideSwitchPrompt`; in every other game no mid-game switch prompt or line is produced.
- The Game Over sheet shows a separate "Teams change ends." line above the unchanged "Next game starts at 0-0."; the spoken game line says "Change ends." before "Next game, ...".
- Match endings are "Game and match, <winner>, <w> to <l>." (best of 1) and "Game N to <winner>, <w> to <l>." + "Game and match, <winner>, <wg> games to <lg>." (best of 3/5).
- Not changed: initial service between games (Open question 2), still "winner serves first".
- Device checks owed: best of 3, game 1 passing 6 is silent and shows no sheet, game 3 passing 6 says "Switch sides." and shows the sheet; between games "Change ends." is spoken and shown; "Side out." on a side-out and "Second server." when the first server loses, neither after undo; "Game point." when serving at 10-8 (not when receiving at 8-10); "Match point." in a clincher; a game ending says "Game and match, ...".
- Undo from a later game back into an earlier game speaks the restored call, plus "Game point."/"Match point." when the restored board is one (no prefix, no switch line).
