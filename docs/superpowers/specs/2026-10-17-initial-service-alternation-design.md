# Initial Service Alternation Design

**Date:** 2026-10-17
**Status:** Approved and built (see "As built")
**Builds on:** `docs/superpowers/specs/2026-10-17-official-calls-and-change-of-ends-design.md` (Open question 2 there)

## Goal

Two related changes about WHO is serving: (1) follow the official rule for who serves first in each game; (2) make the announcer name the team that has the serve after a side-out (user request, 2026-10-17).

Part 1 first: follow the official rule for who serves first in each game. The 2026 USA Pickleball Official Rulebook, Rule 21.F.2: "Singles players or doubles teams must change ends and initial service for the next game of the match." The app today gives the next game's first serve to the previous game's **winner** (`PickleballMatch` creates the next game with `firstServingTeam: winner`). Under the rule, initial service **alternates every game**: the team that served first in game 1 receives first in game 2 and serves first again in game 3.

The user approved "follow the rule by default, no setting to keep the old behaviour" (2026-10-17).

## Behaviour

- **Game 1:** unchanged. The coin flip / manual spin result (`ActiveMatchController.confirmFirstServe`) decides who serves first.
- **Game N+1:** the team that did NOT serve first in game N. So game 2 is the opponent of game 1's first server; game 3 is the opponent of game 2's, i.e. the same team as game 1; best of 5 alternates the same way.
- The first server of a game is independent of who won the previous game. A score correction that flips a game's winner changes the games-won tally but never changes who serves first in the next game.
- The doubles starting server within the serving team, and the 0-0-2 start, are unchanged. Rule 21.F.3 (a team may change its starting server between games) is out of scope.
- Singles, rally scoring (with or without freeze) and all match formats follow the same alternation.
- No setting. The old "winner serves" behaviour is removed.

## What the code does today (verified)

- `PickleballMatch.init(... firstServingTeam: ...)` creates game 1; the match does not store who served first. `recordPoint(for:)` creates the next game with `firstServingTeam: winner` (PickleballMatch.swift ~line 86) and `reconcileCurrentGame` does the same with `newWinner` when a correction or undo ends a game (~line 167). Those are the only two creation sites.
- `PickleballGame.history: [GameState]` is the undo stack (public read). Every point, timeout and correction appends the state BEFORE the change; `undo()` pops. Nothing truncates it. The in-progress snapshot (`MatchSnapshot.GameSnapshot { state, history }`) persists `state` and `history` for the current AND every completed game, and the resume initialiser restores them. No persistence code references `servingTeam`.

## Design

- **No schema change.** A game's initial server is derivable from data that is already stored: `PickleballGame.initialServingTeam: Team` = `history.first?.servingTeam ?? state.servingTeam`. (If the game has any move, `history.first` is the state before the first move, whose `servingTeam` is the initial server; if every move was undone or none happened, `state.servingTeam` still is the initial server.) New public read-only computed property, no stored field, no Codable change, so matches saved by earlier builds and mid-match upgrades keep working.
- **Both creation sites** use `completedGame.initialServingTeam.opponent` (`Team.opponent` already exists) instead of the winner: in `recordPoint` the just-completed game is `currentGame`; in `reconcileCurrentGame` it is the game being archived. Undo that un-completes a game restores the earlier game object unchanged (no creation), so nothing else changes.
- **Say who serves first (the first server is no longer the winner).** Because players will no longer be able to assume "the winner serves", the app states it:
  - The Game Over sheet gets one more separate text line: `"First serve: <name>."` (its own element, above "Next game starts at 0-0.", below "Teams switch sides."). The "First serve: <name>." form is grammatical for a singles name, a combined doubles name ("Delon & Katie") and the "Team A"/"Team B" fallback, unlike "<name> serves first.".
  - The spoken game-ended line becomes `"Game 1 to Delon, 11 to 3. Switch sides. Next game, Fred serving, 0, 0, 2."` (server name inserted before the call; the planner already has the new game's `servingTeam` in the snapshot and the team names).
  - The Game Over prompt carries the new first server's name (a new associated value on the prompt). It is read from `match.currentGame.state.servingTeam` at the moment the prompt is created: by then `PickleballMatch` has already archived the finished game and replaced `currentGame` with the fresh next game, so that value IS the next game's first server (map `.teamA` to `activeMatchController.teamAName`, `.teamB` to `teamBName`). Also true for the Correct Score sheet path that ends a game.
- **How to Play** text (HowToPlayView) gains one sentence: after every game the teams switch sides and the other team serves first (Rule 21.F.2).

### Name the serving team on a side-out (decided with the user: keep "Side out." and add the team)

"Side out." tells the court that possession changed but not who has it. After a side-out the announcer now says the new serving team's name as its own sentence, between the official call and the score call:

- Doubles or singles side-out scoring, forward move, serving team changed (the existing "Side out." condition): `["Side out.", "<new serving team name> serving.", "<call>."]`, e.g. `"Side out. Fred serving. 2, 4, 1."`.
- "Second server." is unchanged (the SAME team keeps the serve, so no team name).
- Slot order of one same-game change becomes: (1) prefix: `"Side out."` + `"<name> serving."` (two sentences) or `"Second server."`, (2) score call, (3) switch line, (4) stakes. Example with stakes: `["Side out.", "Delon serving.", "10, 8, 1.", "Game point."]`.
- Same forward-move-only rule as "Side out." (never after undo or correction), side-out scoring only; rally scoring never says "Side out." or a serving team name.
- Names are spoken as entered (the combined doubles name, or the "Team A"/"Team B" fallback).
- The new-game line already names the first server: `"Next game, Fred serving, 0, 0, 2."`; both uses of the phrase are "<name> serving".
- Planner tests: side-out in doubles and singles with Team A and Team B as the new server (the name is the NEW server's), side-out into game point (four lines), undo of a side-out stays silent, second server has no team name, rally has none.

## Edge cases

- Correction that ends game 1 (non-final) from a state: next game's first server = opponent of game 1's first server, not the winner.
- A correction that FLIPS the winner of a game that was already counted (engine-only path; the UI does not expose it, because the score zones are disabled once the match is over): the replacement next game still uses the opponent of the first server. Undoing across such a flip hits the already documented `undo()` Branch 3 limitation from the score-correction spec (Branch 3 does not reconcile); that is a pre-existing, UI-unreachable limitation and stays out of scope here.
- Undo of a game-ending point, then replaying it: the recreated next game has the same first server as before.
- Best of 3 going to a deciding game: game 3 first server = game 1 first server.
- A match restored from an in-progress snapshot taken under the old build, mid-match: games already created keep their stored state; only games created afterwards follow the new rule (a match that was in game 2 under "winner serves" will have game 3 follow the alternation from game 2's actual initial server).
- Demo point cap / free tier: unaffected.
- `initialServingTeam` of a restored game with a persisted history: first element of history; of a game with no history: its state.

## Testing

PickleballKit unit tests (fast, exact): alternation across games for best of 3 and best of 5 with Team A and Team B winning in different orders; a game won by the first server's opponent and by the first server both give the same next first server; singles and rally; `initialServingTeam` for a fresh game, after moves, after all moves undone, after a correction, and after a snapshot round-trip; a correction that flips a decided game's winner does not change the next first server; undo then replay recreates the same first server; resume mid-match then finish the game keeps alternating. Existing tests that must change (found by a grep before writing this): any multi-game test that plays game 2 by tapping `recordPoint(for: .teamA)` eleven times assumes the game-1 winner also serves first in game 2. Under alternation, if Team A served first in game 1, Team B serves first in game 2, so Team A's first rally win is only a side-out and 11 taps leave the game at 10-0. Affected: about 14 loops in `ServerTwoTests/ActiveMatchControllerTests.swift`, the multi-game tests in `PickleballMatchCorrectScoresTests` (loops at ~lines 70, 94, 122, 140, 159 and the `servingTeam` assertion at ~56), `PickleballMatchRehydrationTests` (~line 8), and the two "winner serves next game" assertions in `PickleballMatchTests` (~lines 21 and 107). Fix with one shared test helper that plays out a game for a chosen winner without assuming who serves (tap the winner's `recordPoint` until `completedGames.count` rises or the match is over, bounded at 200 taps), and change the serving-team assertions to the alternation expectation with a comment naming the rule. The plan must list every affected test file and the implementer must run the complete PickleballKit and app suites to find the rest. App tests: planner test for the new spoken wording; Game Over sheet static-text test for the new line; the existing UI test that reaches the Game Over sheet asserts the new line (`"First serve: Team B"` is wrong for a coin-flip result; assert via the element with the `First serve:` prefix, since the UI-test coin flip may favour either team). Manual (user): best of 3, coin flip gives Team A first serve; after game 1 the Game Over sheet says Team B serves first even if Team A won; game 3 starts with Team A; the spoken line names the server.

## Out of scope

Naming the serving team on a scoring point or on "Second server." (only on a side-out and at a new game);

A setting for the old behaviour; choosing the starting server (which partner) per game (Rule 21.F.3); a new coin toss for a deciding game; any change to saved match history; point-by-point event derivation.

## Open questions with proposed defaults

1. **Announce and show who serves first.** Default: yes (spoken name + sheet line), because the winner no longer serves.
2. **Mid-match upgrades.** Default: only games created after the upgrade follow the new rule; no migration.
3. **The tie-breaker (deciding) game.** Real tournaments may use a new coin toss for it; the rulebook text found says only that initial service changes each game. Default: alternate (no new toss).

## As built

- `PickleballGame.initialServingTeam` (`history.first?.servingTeam ?? state.servingTeam`) is derived, with no stored field or Codable change. Both next-game creation sites in `PickleballMatch` use `currentGame.initialServingTeam.opponent` (Rule 21.F.2); the first server alternates every game and no longer depends on who won.
- The announcer says "Side out." followed by "<new serving team> serving." on a forward side-out in side-out scoring, and "Next game, <first server> serving, <call>." when a game ends; "Second server." has no team name. The Game Over sheet shows "First serve: <name>." between "Teams switch sides." and "Next game starts at 0-0."; the prompt's `firstServerName` is read from `match.currentGame.state.servingTeam` (already the new game).
- Existing multi-game tests were updated through `playOutGame` helpers (PickleballKit test target and `ActiveMatchControllerTests`); each kept its intent.
- Not changed: `undo()` Branch 3's documented limitation; Rule 21.F.3 (starting server within a team).
- Device checks owed: best of 3: after game 1 the Game Over sheet says the OTHER team than game 1's first server serves first, whoever won, and the spoken line names it ("Next game, <name> serving, 0, 0, 2."); game 3 starts with game 1's first server; "Side out. <name> serving. ..." names the new serving team and is not spoken after undo; "Second server." has no name.
