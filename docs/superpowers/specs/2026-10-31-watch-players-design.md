# Watch Players Design

**Goal:** Let the Watch app name the players in a match (pick saved players from the phone, or type a new one) so a match finished on the Watch arrives on the iPhone already attributed to real players, with no Edit Players step. Follow-up to the Watch app (`2026-10-30-watch-app-design.md`), which scores every match as "Team A" and "Team B".

## Today (facts from the code)

- The Watch store is local-only; it never sees the phone's `SavedPlayer` rows (CloudKit, iPhone only).
- `SyncedMatchPayload` (schemaVersion 1) carries `teamAName` / `teamBName` strings only. `importSyncedMatch` stores two `TeamSide`s with those names and no linked players.
- The phone-to-Watch channel is `PhoneStateContext` (`updateApplicationContext`, keys `proUnlocked` and `completedMatchCount`; `init?(applicationContext:)` fails unless both are present). The phone pushes it only when that state changes.
- `StandaloneMatchSession` restores a match after a relaunch with the default team names (the snapshot has no player data).
- `TeamNaming.joinedName` builds a side's name from player names (" & " joined; placeholder when blank).

## Decisions

1. **Optional and quick.** Home gets a "Players" row. Skipping it starts a match exactly as today. The last selection is remembered (UserDefaults, like `LastUsedRules`) and shown on Home, because a court session replays the same players; one tap clears it.
2. **Slots follow the play mode.** Singles: one slot per side. Doubles: two per side. Tapping a slot opens a list: "Me" first, then the phone's saved players (most recent and most frequent first, as the phone orders them), then "New player..." (Watch text input: dictation, Scribble or keyboard) and "Clear". Names show in the slots; the same player on both sides, or twice on one, is refused with a reason line (same rule and wording as the phone's setup).
3. **Phone to Watch: the player list.** `PhoneStateContext` gains an optional `players` entry: an array of `{id (UUID string), name, isMe}`, ordered, capped at 40, names only (no photos). Absent or malformed means an empty list; the existing two-key parse stays valid for old phones and old Watches. The phone pushes it when the list changes (debounced), at session activation and with the existing triggers. The Watch caches the last list in UserDefaults and works from the cache offline.
4. **Watch to phone: additive payload fields.** `SyncedMatchPayload` gains optional `teamAPlayers` and `teamBPlayers`: arrays of `{savedPlayerID: UUID?, name: String}`. `schemaVersion` stays 1: an old phone's decoder ignores the new keys and still imports the match by `teamAName` / `teamBName` (no worse than today); a new phone uses the player arrays. `teamAName` / `teamBName` are always filled (`TeamNaming.displayName`), so every reader keeps working.
5. **Phone import links players.** For each entry: the `savedPlayerID` if that player still exists on the phone and its name still matches case-insensitively; otherwise `upsertSavedPlayer(name:)` (which links an existing same-name player or creates one). A player id the phone does not know falls back to the name. Result: new Watch-typed names become saved players on the phone, exactly like names typed in match setup. Entries are validated like the other payload fields (trimmed, non-blank, at most 64 characters, at most 2 per side); invalid entries are dropped and the match still imports with its name strings. Import stays idempotent and atomic (players and match in one save).
6. **Same-name rule.** Identity is the id when the Watch picked a saved player, the case-insensitive name when the Watch typed one. Two different saved "Mike"s therefore stay apart when picked from the list; a typed "Mike" links to the existing player of that name (the phone's behaviour). Documented, not prevented.
7. **Session and resume.** `StandaloneMatchSession.start` takes the selection; `teamName(for:)` and the saved record use `TeamNaming`. The in-progress snapshot stores the selection (optional fields, so older snapshots decode with default names), so a relaunch mid-match keeps the names.
8. **Scoring screen.** Names are already one line with a 0.5 scale factor; doubles reads "Mike & Sarah". No layout change; verify on 40 mm at large text.
9. **Privacy.** Player names now also live on the Watch (local) and travel phone to Watch over Apple's device-to-device link. The privacy page gets one sentence. Nothing leaves the user's devices.

## Not in scope

Photos on the Watch, editing or deleting players on the Watch, per-player stats on the Watch, ordering controls, live mirroring of a match between the devices (a separate project).

## Tests (kit, written first)

- `PhoneStateContext`: round trip with players; old two-key dictionary parses with an empty list; malformed player entries are dropped; cap at 40.
- Payload: old JSON (no player keys) decodes; new fields round trip; stable encoding.
- Import: id match; id unknown; id with a changed name; typed name equal to an existing player in another case; new name creates one player (not two for two sides); blank, over-long and over-count entries; same player on both sides; idempotent resend; old payload still imports names only.
- Session: start with players; names in `teamName(for:)`; saved record has joined names; snapshot round trip and an old snapshot; selection store (persist, clear, cap, defaults).
- Slot validation: duplicate refusal and reason text match the phone's.

## Not verifiable here

Real-device behaviour of the Watch text input (dictation, Scribble), the phone's debounced push arriving while the Watch app is closed, and the look of long names on a 40 mm Watch.
