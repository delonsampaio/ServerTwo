# Official Calls and Change of Ends Design

**Date:** 2026-10-17
**Status:** Draft for review (Gemini review, then user review, before a plan is written)
**Builds on:** `docs/superpowers/specs/2026-10-16-voice-announcer-design.md` (the announcer as built)

## Goal

Two related changes found while asking "what is the official way to announce a score":

1. **Make the announcer sound more like a real referee**: add "Side out.", "Game point." / "Match point.", and the official-style game/match endings.
2. **Follow the official change-of-ends rule.** Today the app prompts "Switch Sides" (and now speaks "Switch sides.") at the midpoint of EVERY game. The rule says teams change ends after every completed game, and change ends mid-game only at the midpoint of the LAST game of the match format.

The user delegated the choices to the controller ("for 1 and 2 do what is best"); the user declined the separate "best installed voice" idea. This spec records what was chosen and why.

## Verified rule text

From a third-party reproduction of the 2025 USA Pickleball rulebook, Section 5 (https://www.playpickleball.com/2025-usa-pickleball-rules-section-5-service-and-end-selection-rules/). The official PDF could not be fetched, so the wording below should be confirmed against the official rulebook before release; the rule numbers are as printed on that page.

- **5.B.1:** "Teams change ends and initial service upon the completion of each game."
- **5.B.2:** Two minutes are allowed between games.
- **5.B.3:** "In matches that consist of a single game, the teams will change ends at the midpoint based on the match format" (6 in a game to 11, 8 to 15, 11 to 21). Serve remains with the player holding serve.
- **5.B.4:** In a multi-game match, ends change at the midpoint of the LAST game, based on the match format (example 6 in a game to 11).
- **5.B.5:** One minute is allowed to change ends during a game.

Not verified, deliberately NOT part of this spec: the same rule says "initial service" also changes after each game (the team that served first does not serve first again); the app currently gives the next game's first serve to the previous game's winner. See Open question 2.

Conventions (not rulebook text, per two Gemini answers and no counter-evidence found): "Side out", "Game point", "Match point", "Game and match" are referee/broadcast conventions. No rule numbers for them are cited anywhere in this project.

## Decisions

1. **Add "Side out."** before the new score call when possession changes. Side-out scoring only (rally scoring has no side-outs). Spoken only on a FORWARD move, never on undo or correction.
2. **Add "Game point." / "Match point."** after the score call. See "Game point rule" below.
3. **Skip "Second server."** The call already ends in "2"; it would fire every time the first server loses.
4. **Official-style endings:**
   - Best of 1: `"Game and match, <winner>, <winner score> to <loser score>."`
   - Best of 3/5 clincher: `"Game <N> to <winner>, <winner score> to <loser score>. Game and match, <winner>, <winner games> to <loser games>."` Wording for the games tally is spoken as "2 games to 1" (not "2 to 1") so it is not mistaken for a point score.
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

Let `target = winningScore`, a team is "at game point" when it can end the game by scoring the next point.

- **Side-out scoring and rally freeze:** only the SERVING team can end the game on the next rally (a receiving team's rally win is only a side-out), so game point exists only for the serving team. Condition: `configuration.isCompletedGameScore` is true for the serving team's score + 1 with the other score unchanged. This reuses the existing win-by-2 / overtime logic.
- **Rally without freeze:** either team can end the game on any rally, so game point applies if EITHER team satisfies the condition for itself.
- **Match point:** game point AND the team that would win the game has `gamesWon + 1 >= matchFormat.gamesToWin`.
- Spoken after the call (so the score is never delayed). It is a description of the board, so it is also spoken after an undo or correction that lands on such a board (when a call is spoken).

### Change of ends in the UI

- `ScoringView`'s side-switch prompt logic (`syncSideSwitchPrompt` and the correction sheet's `onDismiss` re-check) only enqueues a side-switch prompt when the current game index equals `matchFormat.rawValue - 1` (the last game of the format). The per-game-index tracker, queue, stale-drop and resume seeding stay as built.
- The Game Over sheet's caption changes from "Next game starts at 0-0." to "Teams change ends. Next game starts at 0-0."
- The engine's `hasSideSwitched` flag is unchanged; it simply is not acted on in non-last games.

### Resume and undo

- A resumed match behaves the same: nothing is spoken or prompted on appearance.
- Undo from the last game back into an earlier game (the game index falls) speaks only the restored call, as today.

## Architecture

- `AnnouncementSnapshot` gains `moveCount: Int` (`match.currentGame.history.count`). `AnnouncementPlanner.plan` already receives `matchFormat` and `configuration`; it computes the last-game gate (`new.gameIndex == matchFormat.rawValue - 1`), game/match point, and the side-out line itself. No new parameters on `plan`.
- A tiny pure helper on `MatchFormat` (app target) names the gate once, so the planner and `ScoringView` share it: `isLastGame(index:)`.
- `ScoringPromptSheet`'s Game Over caption text becomes a testable static helper with the new wording.
- No PickleballKit changes.

## Edge cases to handle

- Game point/match point in overtime (win by 2): 10-10 → no; 11-10 serving → yes; 12-11 → yes.
- Match point only when the game win would clinch the match; best of 1 every game point is match point.
- A correction landing on a game-point board speaks the call plus "Game point." (descriptive).
- An undo that restores the serving team does NOT say "Side out." (move count fell).
- The first game of a best of 3 reaching 6: no "Switch sides." and no prompt; game 3 reaching 6: both.
- Existing UI tests: the scoring-prompt and score-correction UI tests use the default best-of-1, where the prompt still applies; the Game Over UI test uses best-of-3 game 1 and is unaffected except the caption text if it asserts it.
- Rally freeze serving-only vs non-freeze either-team (above).

## Testing

- Planner unit tests (exact strings): "Side out." forward in singles and doubles side-out; not on undo; not in rally; game point for the serving team only (side-out), either team (rally non-freeze); not at 8-10 with the 10-point team receiving; overtime cases; match point; the three ending wordings; "Change ends." line; switch lines gated by last game for best of 1/3/5.
- A pure test of `MatchFormat.isLastGame(index:)`.
- A test of the new Game Over caption helper.
- `ScoringView` gating covered by one UI test: a best-of-3 game 1 corrected to 6-0 shows NO Side Switch sheet (assert absence), while the existing best-of-1 test still shows it. Keep the UI test count low: extend an existing test where possible.
- Manual (user): best of 3, game 1 passing 6 → silent; game 3 passing 6 → "Switch sides."; game over between games says "Change ends."; "Side out." on a side-out and not after undo; "Game point." when serving at 10-8; "Match point." in a clincher.

## Out of scope

Initial-service alternation between games (Open question 2), "Second server", "Fault", "Let", medical timeouts, a settings toggle for the old switching behaviour, an announcement or prompt for the 2-minute / 1-minute change-of-ends timers.

## Open questions with proposed defaults

1. **Verify the change-of-ends rule against the official 2026 rulebook PDF** before release (only a third-party reproduction of the 2025 text was available). Default: implement as above.
2. **Initial service between games.** Rule 5.B.1 says initial service changes with each game, while the app gives the next game's first serve to the previous game's winner (`PickleballMatch.recordPoint` creates the next game with `firstServingTeam: winner`). Default: leave unchanged, record in the roadmap as a possible follow-up, since it changes engine behaviour and persisted matches.
3. **"Change ends." on every game break** even for players who do not follow the rule. Default: yes (it is the rule).
