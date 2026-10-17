# Voice Announcer Design

**Date:** 2026-10-16
**Status:** Gemini review applied (see "Review changes" at the end); awaiting user review before a plan is written

## Goal

Make the existing **Voice Announcer** toggle (Settings → Audio & Haptics) do what it says. While a match is on the scoring screen, the app speaks the pickleball score call after each score change, plus short callouts for the moments the app already treats as events: side switch, timeout, game over, match over.

Today `AppSettings.voiceAnnouncerEnabled` is stored (default `true`) but nothing reads it: there is no `AVSpeechSynthesizer` or `AVFoundation` code anywhere in the app. Deferred earlier as "Phase 7"; the original design lists "AVSpeechSynthesizer voice announcer, toggled in settings".

## Decisions made with the user

1. **Scope: score call plus events** (not score call only, not events only).
2. **Audio behaviour: speak even when the phone is on silent, and duck other audio** (music/podcast dips while a call plays, then returns). The Settings toggle is the opt-out.
3. **Default OFF** (changed 2026-10-17 at the user's request after trying it: `AppSettings.voiceAnnouncerEnabled` now defaults to `false`; a user who turns it on keeps their choice).

## What is spoken

> **Superseded in part by `2026-10-17-official-calls-and-change-of-ends-design.md`:** the mid-game "Switch sides." / "Switch back." lines now apply only in the last game of the match format; match endings are "Game and match, ..." (not "<winner> wins ..."); "Switch sides." is spoken between games; "Side out.", "Second server." and "Game point."/"Match point." were added. Do not revert the code to the wording below.

The call format, from the in-app How to Play text ("serving team's score, receiving team's score, then which server is up (1 or 2)"):

- **Doubles, side-out scoring:** three numbers: `"<serving team score>, <receiving team score>, <server number>"`, e.g. `"4, 2, 1"`.
- **Singles, or rally scoring (either play mode):** two numbers: `"4, 2"`. The engine resets `serverNumber` to `.one` after every rally point, and the server number is not part of a rally-scoring call.

The serving team's score always comes first (`state.servingTeam`, `state.score(for:)`).

The planner checks the completed-game count FIRST: if it changed, only the game/match lines apply and the rows below it (side switch, timeout, plain score call) are skipped, so a single multi-field change never produces conflicting lines.

Announcements are derived by comparing the **previous** and **new** state of the scoring screen (see Architecture), not from which button was pressed, so a tap, an undo, a Correct Score save and an accessibility action all behave the same.

| Change (old → new) | Spoken |
|---|---|
| Score or serve state changed, same game | the score call, e.g. "4, 2, 1" |
| ...and `hasSideSwitched` went false → true | the score call, then "Switch sides." |
| ...and `hasSideSwitched` went true → false (today only an undo can do this; see Open question 5 about corrections) | the score call, then "Switch back." |
| A team's timeouts remaining decreased | "Timeout, <team name>." |
| A game completed, match continues (completed-game count rose) | "Game <N> to <winner>, <winner's score> to <loser's score>. Next game, <call for the new game>." The winner's score is always spoken first, whichever team won. |
| The game that completed also ended the match | best of 1: "<winner> wins, <winner's score> to <loser's score>." Best of 3/5: "Game <N> to <winner>, <winner's score> to <loser's score>. <winner> wins the match, <winner's games> to <loser's games>." |
| Completed-game count fell (undo into the previous game) | the score call only, no events |
| Timeouts increased (undo of a timeout), or nothing audible changed | nothing |

Rules:
- The new game's call after a completed game is "0, 0, 2" in doubles side-out, "0, 0" otherwise. No side-switch or score-call line is added on top of the game-over line.
- Team names are spoken as entered (`teamAName` / `teamBName`, falling back to "Team A" / "Team B" when blank).
- Undo and correction announce the resulting board once, in the same voice. No "correction" wording.
- Nothing is spoken when the scoring screen first appears (a resumed match stays silent until the next change), and nothing is spoken for Cancel Match or for opening/cancelling the Correct Score sheet.

## Behaviour

- **Latest wins.** If a new announcement arrives while speech is in progress (fast scoring), the current speech is cut off and the new announcement is spoken. A stale call is not useful. One announcement is ONE utterance: the planner returns separate lines (easy to assert in tests) but `VoiceAnnouncer` joins them into a single string ("4, 2, 1. Switch sides.") so only one `AVSpeechUtterance` is ever in flight and finish/cancel callbacks cannot be confused between the lines of one announcement.
- **Respects the toggle live.** Turning the toggle off stops any speech in progress. The stop is wired where the toggle lives (an `onChange` on `appSettings.voiceAnnouncerEnabled` in the Settings view, or a callback from `AppSettings`), not inside `ScoringView`, which is not on screen while the user is in Settings. Speech also stops when the app leaves the foreground (`scenePhase` not `.active`).
- **VoiceOver:** if VoiceOver is running, the announcer stays silent in v1 (VoiceOver already reads the score zones' label changes; double speech is worse than none).
- **Audio session:** category `.playback`, mode `.voicePrompt` (Apple's mode for brief spoken prompts), options `[.duckOthers, .interruptSpokenAudioAndMixWithOthers]`: music ducks, and podcast/audiobook audio pauses for the call instead of two voices overlapping, then resumes. Verify the exact mode/option behaviour on a device (open question 4). Set the category once; activate when a call starts. `.playback` plays through the silent switch and routes to Bluetooth/AirPods by default. No background-audio capability is needed (announcements happen only while the scoring screen is on screen).
- **Deactivation is debounced, and callbacks are identity-checked.** `stopSpeaking(at: .immediate)` followed by a new `speak` means the cancelled utterance's `didCancel` can arrive AFTER the new utterance has started. So `SystemSpeechOutput` remembers the current utterance and ignores delegate callbacks for any other utterance, and calls `setActive(false, options: .notifyOthersOnDeactivation)` only after ~1.2 s with no new utterance (a cancellable task, restarted by each speak). This avoids a session-busy deactivation error, music pumping up and down between rapid calls, and tearing down a warm Bluetooth route between points.
- **Bluetooth lead-in:** when speech starts from an inactive session, set a short `preUtteranceDelay` (start at 0.15 s; tune on device) so a waking Bluetooth route does not swallow the first number; no delay while the session is still warm from a recent call.
- **Concurrency:** the project builds in Swift 5 mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so types are `@MainActor` by default. The `AVSpeechSynthesizerDelegate` methods must be `nonisolated` and hop to the main actor carrying the utterance identity for the check above.
- **Voice and rate:** the system default voice for the device language, default rate and pitch. No voice picker in v1.
- **UI tests:** speech is replaced by a null output on a UI-test launch (the `-UITest-ResetState` launch argument that every UI test already passes, handled in `MyApp`), so tests never touch the audio session.

## Architecture

All new code is in the app target (`ServerTwo/`), not PickleballKit: it is presentation, and it uses `AVFoundation`.

- **`AnnouncementSnapshot`** (Equatable value type): the facts the planner needs: `gameIndex` (= `completedGames.count`), team scores, `servingTeam`, `serverNumber`, `hasSideSwitched`, both teams' timeouts remaining, both teams' games won, `isMatchOver`, and the just-completed game's final score and winner (when there is one). Built from `PickleballMatch` by one initializer.
- **`AnnouncementPlanner`** (pure, stateless): `static func plan(from old: AnnouncementSnapshot, to new: AnnouncementSnapshot, configuration: GameConfiguration, teamAName: String, teamBName: String) -> [String]` returning the ordered lines to speak (empty = silent). Contains the call formatter and every rule in the table above. This is where almost all the tests live.
- **`SpeechOutput`** (protocol): `speak(_ text: String)`, `stop()`. Implementations: `SystemSpeechOutput` (AVSpeechSynthesizer + the audio-session handling above, delegate callbacks for finish/cancel) and `NullSpeechOutput` (UI tests). Tests use a recording fake.
- **`VoiceAnnouncer`** (`@Observable`, owned in `MyApp` next to `AppSettings`, injected through the environment): `announce(_ lines: [String])` checks `AppSettings.voiceAnnouncerEnabled` and `UIAccessibility.isVoiceOverRunning`, joins the lines into one string, interrupts current speech, speaks. `stop()` when the toggle turns off.
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
- Planner tests must include Team B winning a game and a match (winner's score/games spoken first), a best-of-3 clincher (final game score then match line), and the gameIndex-first rule.
- `VoiceAnnouncerTests` with a recording fake `SpeechOutput` (lines are joined into one string; toggle-off and scene-inactive both stop speech): disabled toggle speaks nothing and stops speech when turned off; VoiceOver-running speaks nothing; a new announcement interrupts the previous one.
- No UI test (audio cannot be asserted). One check that UI-test launches use the null output.
- The simulator misleads for audio: it cannot show silent-switch behaviour, background-music ducking, Bluetooth wake clipping, and a fresh simulator may lack a downloaded TTS voice (callbacks fire with no sound). Keep logic tests on the fake output and verify audio on a physical iPhone only.
- Manual device checks (user): hear the calls in a doubles game; side switch and timeout callouts; undo; game over in a best-of-3; music ducks and returns; AirPods/Bluetooth; toggle off silences; silent switch on still speaks.

## Out of scope (v1)

Voice picker, speech rate setting, volume setting, other languages, announcing the first serve at match start, announcing player names or court sides, the Apple Watch, and a pre-recorded audio option.

## Open questions with proposed defaults

1. **Skip when VoiceOver is running?** Default: yes (silent in v1).
2. **"Next game, 0, 0, 2." after a game ends:** default: include it. (Alternative: end after the game-over line.)
3. **Wording:** "Switch sides." / "Switch back." / "Timeout, Delon." / "Game 1 to Delon, 11 to 3." Default as written; the user can reword.
4. **Verify on device** that `.playback` + `.voicePrompt` + `[.duckOthers, .interruptSpokenAudioAndMixWithOthers]` ducks music, pauses and resumes a podcast, and restores both as intended, and that a Bluetooth route is not delayed or clipped (tune `preUtteranceDelay`).
5. **Corrections below the threshold never flip `hasSideSwitched` back.** `PickleballGame.correctScores` only ever sets the flag false → true (via `checkSideSwitch`); only `undo()` restores it to false. So a downward correction (6-2 → 5-2) leaves the sides "switched", with no Switch Back prompt or announcement, although the Switch Back sheet's design assumed corrections would also do it. Proposed: a small engine change so `correctScores` recomputes the flag from the corrected scores (flag = max score ≥ threshold), with tests; then undo/correction behave alike for the prompt and the announcement. Needs the user's decision (default: make the change).

## Review changes (Gemini, 2026-10-17)

Applied after verification against the code: one utterance per announcement and identity-checked, debounced deactivation (race between `didCancel` and the next `speak`); winner-first score order in the game/match lines (the old "<a> to <b>" wording was ambiguous); final-game score before the match line in best-of-3/5; `.voicePrompt` mode with `.interruptSpokenAudioAndMixWithOthers`; Bluetooth lead-in delay; toggle-off and scene-phase stop wired outside `ScoringView`; delegate methods `nonisolated` (the project uses MainActor default isolation; it builds in Swift 5 mode, so Gemini's "Swift 6 compile error" claim does not apply as stated); simulator audio caveats; the true → false flag finding, confirmed in `PickleballGame.correctScores`, recorded as open question 5. Not changed: VoiceOver stays silent (Gemini agrees); `onChange(of: snapshot)` as the trigger (Gemini agrees).

## As built

- `AnnouncementPlanner.plan` also takes `matchFormat` (needed for the best-of-1 match-over line), and returns full sentences ending in a period; `VoiceAnnouncer` joins them with a space into one utterance.
- Open question 5 resolved: `PickleballGame.correctScores` now derives `hasSideSwitched` from the corrected scores (flag = max score ≥ threshold), so a downward correction clears a switch like undo does; undo restores the flag.
- New code is under `ServerTwo/Voice/`: `AnnouncementSnapshot`, `AnnouncementPlanner`, `SpeechOutput` (+ `NullSpeechOutput`), `SystemSpeechOutput` (identity-checked callbacks, 1.2 s debounced deactivation, 0.15 s cold-start lead-in), `AVSpeechAdapters` (device-verified only), `VoiceAnnouncer`.
- `MyApp` owns the announcer, stops speech when the toggle turns off or the scene leaves `.active`, and uses `NullSpeechOutput` for any `-UITest-` launch argument in Debug builds. `ScoringView` runs the planner from one `.onChange` on the snapshot.
- Device checks still owed (not verifiable in the simulator): calls audible in a doubles game; "Switch sides." / "Switch back." / "Timeout, <team>." / game and match lines; music ducks and returns; a podcast pauses and resumes; AirPods/Bluetooth first number not clipped; silent switch on still speaks; toggle off silences; a resumed match is silent until the next change; VoiceOver on = silent; a downward Correct Score edit under the threshold is spoken ("... Switch back.") and shows the Switch Back sheet after the Correct Score sheet closes.
- Additional device checks: leaving the foreground INCLUDING `.inactive` (Control Center / a system alert pulled down mid-call) stops speech; double-tap two points quickly and tap undo several times, and the LAST call is heard (`stopSpeaking` immediately followed by `speak`); no visible lag on a score tap with AirPods connected (activation runs synchronously on main; if there is lag, move activation to a serial queue); after the last call of a match, music un-ducks within a couple of seconds.
- Voice language: an English voice is used whenever the device language is not English, because all announcement text is English (`AVSpeechSynthesizerAdapter.voiceLanguage(deviceLanguage:)`).
- Deactivation retry: if `setActive(false)` fails, the session stays tracked as active and deactivation is rescheduled once; a second failure gives up and the next `speak` activates again.
- Audio session switching is now asynchronous: `AVAudioSessionController` uses the iOS 27 `activate(options:completionHandler:)` / `deactivate(options:completionHandler:)`, and `SystemSpeechOutput` is a state machine (inactive/activating/active/deactivating; latest-wins across the async gap), replacing the synchronous `setActive` calls that triggered the system's main-thread warning. The earlier "device check: tap lag with AirPods" note stays valid.
