# Voice Announcer Design

**Date:** 2026-10-16
**Status:** Draft for review (Gemini review, then user review, before a plan is written)

## Goal

Make the existing **Voice Announcer** toggle (Settings → Audio & Haptics) do what it says. While a match is on the scoring screen, the app speaks the pickleball score call after each score change, plus short callouts for the moments the app already treats as events: side switch, timeout, game over, match over.

Today `AppSettings.voiceAnnouncerEnabled` is stored (default `true`) but nothing reads it: there is no `AVSpeechSynthesizer` or `AVFoundation` code anywhere in the app. Deferred earlier as "Phase 7"; the original design lists "AVSpeechSynthesizer voice announcer, toggled in settings".

## Decisions made with the user

1. **Scope: score call plus events** (not score call only, not events only).
2. **Audio behaviour: speak even when the phone is on silent, and duck other audio** (music/podcast dips while a call plays, then returns). The Settings toggle is the opt-out.
3. **Default stays ON** (the toggle already defaults to `true`; unchanged).

## What is spoken

The call format, from the in-app How to Play text ("serving team's score, receiving team's score, then which server is up (1 or 2)"):

- **Doubles, side-out scoring:** three numbers: `"<serving team score>, <receiving team score>, <server number>"`, e.g. `"4, 2, 1"`.
- **Singles, or rally scoring (either play mode):** two numbers: `"4, 2"`. The engine resets `serverNumber` to `.one` after every rally point, and the server number is not part of a rally-scoring call.

The serving team's score always comes first (`state.servingTeam`, `state.score(for:)`).

Announcements are derived by comparing the **previous** and **new** state of the scoring screen (see Architecture), not from which button was pressed, so a tap, an undo, a Correct Score save and an accessibility action all behave the same.

| Change (old → new) | Spoken |
|---|---|
| Score or serve state changed, same game | the score call, e.g. "4, 2, 1" |
| ...and `hasSideSwitched` went false → true | the score call, then "Switch sides." |
| ...and `hasSideSwitched` went true → false (undo/correction under the threshold) | the score call, then "Switch back." |
| A team's timeouts remaining decreased | "Timeout, <team name>." |
| A game completed, match continues (completed-game count rose) | "Game <N> to <winner>, <a> to <b>. Next game, <call for the new game>." |
| The game that completed also ended the match | best of 1: "<winner> wins, <a> to <b>." Best of 3/5: "<winner> wins the match, <games> to <games>." |
| Completed-game count fell (undo into the previous game) | the score call only, no events |
| Timeouts increased (undo of a timeout), or nothing audible changed | nothing |

Rules:
- The new game's call after a completed game is "0, 0, 2" in doubles side-out, "0, 0" otherwise. No side-switch or score-call line is added on top of the game-over line.
- Team names are spoken as entered (`teamAName` / `teamBName`, falling back to "Team A" / "Team B" when blank).
- Undo and correction announce the resulting board once, in the same voice. No "correction" wording.
- Nothing is spoken when the scoring screen first appears (a resumed match stays silent until the next change), and nothing is spoken for Cancel Match or for opening/cancelling the Correct Score sheet.

## Behaviour

- **Latest wins.** If a new announcement arrives while speech is in progress (fast scoring), the current speech is cut off and the new announcement is spoken. A stale call is not useful. Within one announcement, its lines are spoken in order ("4, 2, 1" then "Switch sides.").
- **Respects the toggle live.** Turning the toggle off stops any speech in progress.
- **VoiceOver:** if VoiceOver is running, the announcer stays silent in v1 (VoiceOver already reads the score zones' label changes; double speech is worse than none).
- **Audio session:** category `.playback`, mode `.spokenAudio`, options `.duckOthers`. Activated when a call starts, deactivated with `.notifyOthersOnDeactivation` when speech finishes or is cancelled, so other audio un-ducks. `.playback` plays through the silent switch and routes to Bluetooth/AirPods by default. No background-audio capability is needed (announcements happen only while the scoring screen is on screen).
- **Voice and rate:** the system default voice for the device language, default rate and pitch. No voice picker in v1.
- **UI tests:** speech is replaced by a null output on a UI-test launch (the `-UITest-ResetState` launch argument that every UI test already passes, handled in `MyApp`), so tests never touch the audio session.

## Architecture

All new code is in the app target (`ServerTwo/`), not PickleballKit: it is presentation, and it uses `AVFoundation`.

- **`AnnouncementSnapshot`** (Equatable value type): the facts the planner needs: `gameIndex` (= `completedGames.count`), team scores, `servingTeam`, `serverNumber`, `hasSideSwitched`, both teams' timeouts remaining, both teams' games won, `isMatchOver`, and the just-completed game's final score and winner (when there is one). Built from `PickleballMatch` by one initializer.
- **`AnnouncementPlanner`** (pure, stateless): `static func plan(from old: AnnouncementSnapshot, to new: AnnouncementSnapshot, configuration: GameConfiguration, teamAName: String, teamBName: String) -> [String]` returning the ordered lines to speak (empty = silent). Contains the call formatter and every rule in the table above. This is where almost all the tests live.
- **`SpeechOutput`** (protocol): `speak(_ lines: [String])`, `stop()`. Implementations: `SystemSpeechOutput` (AVSpeechSynthesizer + the audio-session handling above, delegate callbacks for finish/cancel) and `NullSpeechOutput` (UI tests). Tests use a recording fake.
- **`VoiceAnnouncer`** (`@Observable`, owned in `MyApp` next to `AppSettings`, injected through the environment): `announce(_ lines: [String])` checks `AppSettings.voiceAnnouncerEnabled` and `UIAccessibility.isVoiceOverRunning`, interrupts current speech, speaks. `stop()` when the toggle turns off.
- **Wiring in `ScoringView`:** one `.onChange(of: AnnouncementSnapshot(match))` that runs the planner on (old, new) and hands the result to `VoiceAnnouncer`. `onChange` does not fire for the initial value, which gives the "silent on first appearance / resumed match" behaviour for free. No change to `ActiveMatchController` or the engine.

Why derive from state changes instead of hooking `recordPoint`/`undo`/`correctScores` in the controller: the controller does not know `AppSettings` or team-name-aware wording, the three entry points would each need the same before/after comparison, and accessibility actions and the correction sheet already funnel into the same observable state.

Side-switch and game-over wording is derived from the same transitions the prompt sheets use (`hasSideSwitched` flips within one game index; completed-game count changes), but not from the prompt queue, so a prompt waiting behind another sheet does not delay or duplicate speech.

## Edge cases to handle

- A Correct Score save that crosses the side-switch threshold and also completes the game in the same change: the game-completed row wins (game index changed), no "Switch sides." line.
- A game that completes while the flag was true, with the new game's flag false: not a "Switch back" (the game index changed).
- Undo that un-completes a game restores that game's flag; the game index fell, so the score call alone is spoken.
- Match over: only the match-over line, no "Next game".
- Free-tier demo point cap (`isPaywalled`): when a point is refused nothing changes, so nothing is spoken.
- Rapid undo taps: each produces a new announcement that interrupts the previous one.
- The toggle is switched off mid-speech: speech stops immediately.
- Audio interruption (phone call, Siri): the system cancels speech; the delegate's cancel callback deactivates the session. No retry.

## Testing

- `AnnouncementPlannerTests` (fast unit tests, exact strings): doubles side-out "a, b, 1/2"; singles two-number call; rally two-number call in doubles; serving team B (its score first); every row of the table (switch sides, switch back, timeout for each team, game completed with next-game call, match over best-of-1 and best-of-3, undo across games, timeout undo silent, no-change silent); a correction that crosses the threshold and ends a game; zero scores.
- `VoiceAnnouncerTests` with a recording fake `SpeechOutput`: disabled toggle speaks nothing and stops speech when turned off; VoiceOver-running speaks nothing; a new announcement interrupts the previous one.
- No UI test (audio cannot be asserted). One check that UI-test launches use the null output.
- Manual device checks (user): hear the calls in a doubles game; side switch and timeout callouts; undo; game over in a best-of-3; music ducks and returns; AirPods/Bluetooth; toggle off silences; silent switch on still speaks.

## Out of scope (v1)

Voice picker, speech rate setting, volume setting, other languages, announcing the first serve at match start, announcing player names or court sides, the Apple Watch, and a pre-recorded audio option.

## Open questions with proposed defaults

1. **Skip when VoiceOver is running?** Default: yes (silent in v1).
2. **"Next game, 0, 0, 2." after a game ends:** default: include it. (Alternative: end after the game-over line.)
3. **Wording:** "Switch sides." / "Switch back." / "Timeout, Delon." / "Game 1 to Delon, 11 to 3." Default as written; the user can reword.
4. **Verify on device** that `.playback` + `.duckOthers` + `.spokenAudio` ducks and restores music as intended, and that a Bluetooth route is not delayed.
