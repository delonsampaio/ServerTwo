# Watch App Design

**Goal:** A standalone Apple Watch app that keeps score of a pickleball match at the court with one hand, with no iPhone nearby. This is Phase 5 of the main spec (`2026-10-06-server-two-design.md`, "Watch app", 3.4 Sync, 3.5 Platform points), split into three sub-projects so each ships and is verified on its own.

## Sub-projects

- **A (this spec, built):** the watchOS app target, a platform-neutral match session in `PickleballKit`, a local-only store, and the scoring screens. The Watch scores a whole match on its own and saves the finished match locally.
- **B1 (built, see "Sync (B1)" and "As built (B1)"):** the match sync below. **B2 (built as the free-demo gate, see "As built (B1 fixes + gate)"):** the phone's Pro entitlement on the Watch. Original description of B: WatchConnectivity queue of finished matches to the phone. The Watch sends the matches in its pending-sync set (below) with `transferUserInfo`; the phone saves each into its CloudKit store and dedupes by match UUID (`MatchRecord.id`), then acknowledges so the Watch calls `confirmSynced`. Also decides how the phone's Pro entitlement reaches the Watch: StoreKit `currentEntitlements` on the Watch and a per-device demo counter, handled together with B because both need the phone link.
- **C (built, see "Workout (C)" and "As built (C)"):** `HKWorkoutSession` (pickleball workout) so watchOS keeps the app foregrounded during a match and logs a workout, heart rate on the scoring screen, and the Health permission.
- **Follow-up after device testing:** Digital Crown scoring. Deferred on purpose: whether a crown tick should mean "point for the serving team" or select a team, and how it feels with wet hands, can only be judged on a real watch.

## Decisions (approved)

- **Standalone.** The Watch has its own engine instance and its own local store and works without the phone. A match in progress never leaves the watch (spec 3.4); only a finished match will later be queued to the phone (B).
- **Scoring screen.** Two stacked tap zones, Team A on top and Team B below, each as wide as the screen. Each zone shows the team name ("Team A"/"Team B"; names are optional and default, rich setup stays on the phone where Edit Players can fix a synced match), the big score, the serving badge ("SERVER 1/2" in doubles side-out, "SERVING" otherwise, same wording as the phone) and, for best of 3/5, games won. A dedicated Undo button of at least 44 pt (not a swipe: edge swipes clash with system gestures). Haptic on every point: click for a point, a stronger one for a side-out or second server, success for game over and match over.
- **Quick start.** Home has a Start Match button using the last-used rules (doubles/singles, single game/best of 3/best of 5, side-out/rally), persisted in UserDefaults, and a small Rules sheet to change them. Then a coin flip screen (the kit's `CoinFlip`, with the manual "A served first / B won spin" choice as on the phone), then scoring.
- **Between games.** A game-over screen: "Game 1 to Team A, 11 to 3", "Next game, Team B serving" (the initial server alternates every game, Rule 21.F.2, whoever won), a "Teams switch sides" note and a Next Game button. Scoring is held on that screen so a stray tap cannot score in the next game.
- **Mid-game side switch.** A "Switch sides" notice at the rulebook threshold, only in the last game of the format (Rule 21.B; between games the teams always switch, which the game-over screen says). The pure helpers (`MatchFormat.isLastGame(index:)`, `SideSwitchDirection`, `SideSwitchPromptTracker`) moved from the iOS app into `PickleballKit` as public API with tests; the phone uses the kit versions with unchanged behaviour and tests.
- **Match over.** Winner, final score, Done. "End match?" confirms abandoning (nothing is saved). A persisted snapshot is resumed at launch after a crash or relaunch.
- **Local-only store.** `PersistenceContainer.makeLocalOnlyContainer()`: one SwiftData store with every model and no CloudKit (the Watch target has no iCloud entitlement). A finished match is saved through the existing `MatchRepository.saveCompletedMatch` (default team names, no saved players yet, live game completion dates) and its UUID is added to a persisted pending-sync set (`PendingSyncStore`, UserDefaults key `watchPendingSyncMatchIDs`, ordered oldest first). B consumes that set.
- **Save at match end.** The match is saved the moment the deciding point is scored, not on Done, because a watch app can be suspended or terminated on the match-over screen and a snapshot of a decided match is discarded on relaunch. Undoing the deciding point removes that record and its pending-sync entry again.

## Architecture

- `StandaloneMatchSession` (`PickleballKit/Sources/PickleballKit/Standalone/`): `@MainActor @Observable`, platform-neutral. `start`, `recordPoint` (returns a `PointOutcome` so the UI picks the haptic), `undo`, `startNextGame`, `acknowledgeSideSwitchNotice`, `finish`, `dismissFinishedMatch`, `abandon`, `resumeIfNeeded`, plus read-only derived state (scores, serving team and server number, games won, current game index, `isGameOver` between games, `isMatchOver`, `lastCompletedGame`, `sideSwitchNotice`, serving caption and VoiceOver summary). It follows how the iOS `ActiveMatchController` wraps `PickleballMatch`: a snapshot after every mutation and game completion dates captured live. The iOS controller was not refactored.
- `LastUsedRules`: the persisted rules for Start Match.
- `ServerTwo Watch App` target: SwiftUI views only, no rules logic.

## As built (A)

### What was built

- **`PickleballKit`:** `StandaloneMatchSession`, `LastUsedRules`, `PendingSyncStore`, `PersistenceContainer.makeLocalOnlyContainer(isStoredInMemoryOnly:)`, and the shared `MatchFormat.isLastGame(index:)`, `SideSwitchDirection`, `SideSwitchPromptTracker` (public). 57 new tests (268 in the package, 211 before), all `swift test`. Counted with `grep -c "func test"` per new file: 32 session, 6 side-switch, 5 pending-sync, 3 rules, 9 watch-flow, plus 2 added to `PersistenceContainerTests`; the earlier "209 baseline" was a miscount, the package had 211 test functions before this work. Tests were written before the code they cover except `tapCaption` (added with the screens, test alongside) and a few session tests added in the review-fix round after the first implementation; the first round went RED (compile errors) then GREEN. The kit also builds for watchOS Simulator. The iOS app lost `MatchFormat+LastGame.swift` and `SideSwitchPromptTracker.swift` and uses the kit versions (`ScoringPrompt.SideSwitchDirection` is now a typealias of the kit type, so its call sites and tests are unchanged).
- **`ServerTwo Watch App` target**, folder `ServerTwo Watch App/`: `ServerTwoWatchApp` (container, session, resume at launch), `WatchRootView` (screen chosen by the kit's tested `WatchFlow` from the session state; after Done or End Match the flow shows Home, verified by `WatchFlowTests`, not by tapping a watch), `HomeView` + `RulesSheet`, `CoinFlipView`, `ScoringView` (zones, Undo, End match, side-switch notice), `GameOverView`, `MatchOverView`, `WatchHaptics`, and a DEBUG-only `WatchDemo` (`-Debug-WatchDemoMatch [-Debug-WatchDemoState scoringB|gameOver|matchOver|sideSwitch|coinFlip]`, in-memory store, throwaway defaults suite) used for the simulator screenshots.
- **Colours:** the watch catalog holds the app's `AccentColor`, `AccentText` and `SecondaryText` with only their DARK values as the single appearance. watchOS has no light appearance and picks the catalog's default entry, which rendered the light-mode secondary grey (#5C5C61) on black; no new colour values were introduced. The app icon slot is empty but valid.
- **Dynamic type:** the zone text is capped at xLarge (a zone is a fixed-height surface) and scales down to half size rather than clipping; the system chrome (title, Undo) follows the user's size; VoiceOver reads full labels ("Team A, 7 points, serving, server 2").

### How the target was added

The `xcodeproj` gem cannot write file-system-synchronized projects (objectVersion 90), so `project.pbxproj` was edited by hand, following the Live Activity extension commit. The change is 158 added lines and no removed lines:

- a native target `ServerTwo Watch App` (`com.apple.product-type.application`, `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `TARGETED_DEVICE_FAMILY = 4`, `WATCHOS_DEPLOYMENT_TARGET = 10.0` to match the package's `.watchOS(.v10)`, `SKIP_INSTALL = YES`), bundle id `com.delonsampaio.ServerTwo.watchkitapp`, generated Info.plist with `WKApplication`, `WKCompanionAppBundleIdentifier = com.delonsampaio.ServerTwo` and `WKRunsIndependentlyOfCompanionApp`, same team, automatic signing and Swift 6 settings as the app;
- its own synchronized root group, a Frameworks phase with a second `PickleballKit` package product dependency and build file (the pattern the app and the tests use);
- an "Embed Watch Content" copy phase on the iOS app (`dstSubfolderSpec = 16`, `dstPath = $(CONTENTS_FOLDER_PATH)/Watch`), a target dependency, and `platformFilter = ios` on both so the app's macOS and visionOS destinations do not try to embed it.

The tests' targets and the Live Activity target are untouched. No HealthKit or other entitlement or usage string was added.

### Failure paths and kill-safety

- **Final save fails:** the match is saved the moment it ends. No snapshot is written for a decided match (relaunch discards those anyway), so if that save fails the snapshot from one point earlier is still on disk and a relaunch resumes there; while the app stays alive, Done retries the save and alerts "Couldn't save the match" if it fails again.
- **Undo of the deciding point:** the saved record is deleted and its pending-sync id removed. If the delete fails the record and id are kept as a stale record, and the next save (replaying the deciding point, or Done) deletes it first and then saves, so there is never an orphan plus a second record. If the app is killed before that retry, the stale record stays in the local store and the pending queue; the phone dedupes by match UUID in B, but a duplicate of a replayed match would still reach history, so B should treat it as a known limitation until it can reconcile.
- **Tap latency:** the haptic runs in a callback before the snapshot write (JSON encode, fetch, delete, insert, save) on every point; the write is still synchronous on the main actor. Measure on a device (checklist).
- **`PendingSyncStore`** is `Sendable` and locks every read-modify-write (process-wide lock), because B's WatchConnectivity delegate is a second user; it holds the defaults suite name, not a `UserDefaults` object, since that class is not `Sendable`.

### Pre-release

- **Add iOS and watchOS app icons.** The watch `AppIcon` slot is empty: valid for the build, but an App Store upload will most likely reject it, and the iOS app has no icon either.

### Verified

`plutil -lint` on the project, `xcodebuild -list`, Debug and Release builds of the Watch scheme (watchOS Simulator, fresh compile of every file, no project-source warnings), Debug and Release builds of the iOS scheme (app, Live Activity extension and the embedded `Watch/ServerTwo Watch App.app` in the bundle), the package for watchOS Simulator, a focused iOS test run (`ServerTwoTests` plus `ScoringPromptsUITests`, 371 tests, all passing) to prove the shared-code move did not change the phone, and the screens on the watchOS 27 simulator (40 mm SE 3 and 46 mm Series 12) through the demo launch argument.

### Not verified (nothing was run on a real Watch)

Tapping, haptic feel, battery and Always-On behaviour, Digital Crown, a relaunch after a real termination, and installing the embedded app through the paired phone. The simulator cannot synthesise taps on a watch, so the flow was exercised through the session's unit tests and the demo screenshots, not by tapping the screens.

### Device checklist for the owner

1. Install on a real Watch (through the phone and directly from Xcode) and confirm it launches standalone with the phone off or away.
2. Start Match, Rules sheet changes persist across launches, coin flip both routes.
3. Score a doubles side-out game: serving zone solid, "SERVER 1/2" badge correct, tapping the receiving zone gives second server then side out, and the haptics for point, second server or side out, game over and match over feel distinct.
4. Tap-zone reach with a sweaty finger and the smallest watch you can find; Undo reachable but not accidental.
5. Best of 3: game-over screen, next server alternates, "Switch sides" appears at 6 only in game 3 (or the only game of a single-game match).
6. Wrist down, wait, wake: the match is still there (and force-quit mid-game, relaunch: resumes at the same score). Note whether the app stays foreground between points (without a workout session watchOS may return to the watch face; sub-project C fixes this).
7. Finish a match, then open it with a debugger or logs: one saved record, one pending-sync id.
8. Large text and VoiceOver on the scoring screen.
9. Whether Digital Crown scoring is wanted, and how.
10. Tap latency over a long game (a full best of 5): the haptic should be immediate on every point even late in the match, when the snapshot write is largest.
11. Legibility of the zones on a 40 mm watch, especially the "Tap for 2nd Server" line, in sun and at the largest text size.
12. Done after a finished match lands on Home (not the coin flip), and End Match returns to Home.
13. Archive the iOS app (with the embedded Watch app), Validate, and upload to TestFlight; fix whatever validation says (icons first).

## Sync (B1)

Finished Watch matches reach the iPhone over WatchConnectivity `transferUserInfo`, and the Watch forgets a match only when the phone says it has it. The rules, in the order they matter:

### Payload

`SyncedMatchPayload` (`PickleballKit/Sources/PickleballKit/Sync/`), `Codable`, `Sendable`, `schemaVersion` 1: match id (the `MatchRecord.id`), start and completion dates, format, rules (`configurationData`), winner, both team names and every game with its final score, winner, completion date and point log (sequence number, scorer, score after). JSON with sorted keys and dates as numbers, so a resend is byte-identical. The transfer is `["matchID": uuidString, "schema": 1, "payload": Data]`; the phone's acknowledgement is `["syncedMatchID": uuidString]`. Only the Watch builds payloads, from the saved `MatchRecord`.

### Watch side

- **When it syncs:** only (a) when the user taps Done on the match-over screen (`StandaloneMatchSession.dismissFinishedMatch`) and (b) when `WCSession` finishes activating at launch. Never on a reachability change.
- **Never the undoable match:** the match still on the match-over screen can be undone (the record is deleted). It is excluded (`heldBackMatchIDs`, which is `undoableSavedMatchID` plus a record whose delete failed after an undo). Sending it first would let an undo after the send leave the phone with a match that never finished, plus the replayed one as a second match.
- **Per pending id:** fetch the record by id; no record (orphan: the store fell back to memory, or a crash between marking and saving) means drop the id; skip if `outstandingUserInfoTransfers` already holds a transfer for it; else `transferUserInfo`. A transfer finishing, or failing in `didFinish`, changes nothing: only the phone's acknowledgement confirms, and a failure just leaves the id pending for the next launch or Done.
- **On the acknowledgement:** delete the local record, then `confirmSynced`. The watch has no history screen, so there is no "keep last N". The delete goes first so a failed delete leaves the id pending and the next ack retries it. An ack for a held-back match is ignored (it stays pending, is sent after Done, and the phone answers "duplicate").
- **Crash window:** `markPending(id)` runs BEFORE `saveCompletedMatch` (which takes the id), and `confirmSynced` runs if the save throws. If the save throws after the record was stored (clearing the snapshot is its last step) the record is looked up by id and kept, so a retry cannot save the same match twice.
- **Structure:** the logic is `WatchSyncCoordinator` in the kit behind `WatchSyncTransport`; the real `WCSession` shim, `WatchSessionTransport`, lives in the Watch target.

### Phone side

- **`MatchRepository.importSyncedMatch(_:) -> ImportResult`** (`imported`, `duplicate`, `rejected(reason)`, `unsupportedNewerSchema`): inserts the match, both sides (no players, names as received), games and points in one `save()`, `rollback()` on failure (inserts only, so no staged-delete trap). It never calls `clearInProgressSnapshot()`: a match being scored on the phone keeps its crash recovery.
- **Idempotent, first write wins:** a match whose id already exists, or whose id is in the bounded "seen ids" set (`SeenMatchIDStore`, 500 ids, oldest dropped), is a `duplicate` and nothing changes: an edited match is never overwritten and the demo counter is never touched. The seen set is filled on every import AND by `MatchRepository.deleteMatch` / `deleteAllMatchHistory` (so every phone delete path, including the test reset), so a late resend of a deleted match is not imported again.
- **Versions:** `schemaVersion` above the app's is `unsupportedNewerSchema`: not stored, NOT acknowledged, NOT marked seen, so it is retried after the user updates the phone app. A version the app knows but a payload that is undecodable or invalid is `rejected` and IS acknowledged, so a permanently malformed record cannot loop forever (with no readable id there is nothing to acknowledge). A storage failure is not acknowledged either (transient).
- **Validation before inserting:** rules decode and are sane (timeouts 0...10); game count within 1...(2 x games to win - 1); game numbers 1, 2, 3...; every score pair a legal completed game under the rules (`isCompletedGameScore`, scores at most 99, game winner is the higher score); no game after a team reached games to win; derived match winner equals the payload winner; per game at most 500 points, sequence numbers contiguous from 1, scores 0...99 and never decreasing, last point equals the game's final score (no stricter than the engine, whose manual correction can skip scores); names trimmed, control characters removed, 64 characters at most, empty becomes "Team A"/"Team B" (placeholders pass through unchanged, which is what keeps Edit Players and Rematch treating the side as blank); dates finite, `startedAt` is the earlier of start and completion, a game completion date outside the match window becomes unknown.
- **Demo counter:** for `.imported` only, `ActiveMatchController.recordCompletedMatchSaved(historyCountBeforeSave:)` with the history size read before the insert; never for a duplicate or a reject.
- **Delivery:** `PhoneWatchSync` (app target, not main-actor) is the `WCSession` delegate, created and activated in `MyApp.init` before any view and held by `MyApp`, so a background delivery is not dropped; it handles `sessionDidBecomeInactive` and re-activates in `sessionDidDeactivate`. It decodes on the delegate queue into `Sendable` values, hops to the main actor, and the kit's `WatchMatchReceiver` imports on `modelContainer.mainContext` (the context SwiftUI reads), acknowledges per the table above through `PhoneSyncAcknowledging`, and the app then posts `.matchSyncedFromWatch` for an imported match.
- **Screens:** History, Home and Player detail reload immediately on `.matchSyncedFromWatch` (the timing is the tested `ScreenRefreshTiming`); edits and deletes still wait for the next appearance.
- **History collapses duplicates:** `fetchMatchHistory()` shows one row per match id (a reinstall racing CloudKit can create two), keeping the row with linked players if any.

## As built (B1)

### What was built

- **`PickleballKit`:** the `Sync/` folder (`SyncedMatchPayload` with wire keys, `SyncedMatchMessage`, `IncomingSyncedMatch`; `SeenMatchIDStore`; `MatchRepository.importSyncedMatch` with the validator and `fetchMatchRecord(id:)`; `WatchSyncCoordinator` and `WatchSyncTransport`; `WatchMatchReceiver` and `PhoneSyncAcknowledging`). `MatchRepository` takes an injectable `SeenMatchIDStore`, `saveCompletedMatch` takes an optional `id`, delete paths fill the seen set, `fetchMatchHistory` dedupes by id. `StandaloneMatchSession` gained `undoableSavedMatchID`, `heldBackMatchIDs`, `onFinishedMatchDismissed` and the mark-before-save order. 58 new tests (326 in the package, 268 before).
- **Watch target:** `WatchSessionTransport` (the `WCSession` adapter) and the coordinator started from `ServerTwoWatchApp.init`; a DEBUG-only `-Debug-WatchAutoSyncMatch` launch argument plays one quick match against the real store and taps Done.
- **iPhone target:** `PhoneWatchSync`, the wiring in `MyApp.init`, `.matchSyncedFromWatch` with `ScreenRefreshTiming` in `PlayersEditedRefresh.swift`, and `recordCompletedMatchSaved` made internal. The controller keeps its own `ModelContext`: a test proves its `canStartNewMatch` and the counter see a match imported on the main context, so it was not switched.
- **Side fix (existing bug):** `RematchRequest` split a "Team A"/"Team B" side's name unconditionally, so a Rematch of a match with blank names created real SavedPlayers called "Team A" and "Team B" when the match started. It now uses the same placeholder guard as Edit Players (blank slots). Two tests.

### Decisions the design left open

- Only an `.imported` match posts `.matchSyncedFromWatch` (nothing else changes data).
- An ack for the held-back (undoable) match is ignored instead of confirming it, so it is still sent after Done (the phone answers "duplicate" and acks again).
- The seen set lives in the phone's standard defaults and is also filled when the Watch deletes its own records (undo, after an ack): harmless, bounded, and it keeps one code path.
- A label (`matchID`) that disagrees with the payload's id is rejected and the label is acknowledged.
- Deleting a match on another device (CloudKit) does not reach this phone's seen set; a late resend after that is the one case a deleted match could return (a deletion made on this phone is covered).

### Verified

`swift test` in `PickleballKit`: 326 tests pass. Watch scheme Debug and Release and iOS scheme Debug and Release builds (fresh derived data each, so every file compiled; no project-source warnings in any log; the Release iOS bundle embeds `Watch/ServerTwo Watch App.app`). One focused iOS run (`ServerTwoTests`, `DeleteMatchUITests`, `ScoringPromptsUITests`): 382 tests, all pass (the new app tests: import visible to the controller and counter once, resend and delete-then-resend not counted, a reject not counted, refresh timing, the Rematch guard). Tests that were written after the code they cover (the kit tests were written after the implementation; the RED run was done by stashing the sources, which failed to compile with "cannot find ... in scope"; the app-target tests had no separate RED run).

On a paired watchOS 27 + iOS 27 simulator pair (Series 12 46 mm + iPhone 18 Pro Max), `-Debug-WatchAutoSyncMatch` played a match on the Watch, saved it, marked it pending and called `transferUserInfo` on Done and again at relaunch (visible in the Watch's WatchConnectivity log; the transfer stayed "transferring"). The phone's delegate never received it in over 10 minutes across a reboot of both simulators, so the phone import, acknowledgement and the pending list emptying were NOT observed end to end. The simulator pair reported the companion app as not installed for the first minutes and the transfer queued in the Watch's `UserInfoTransfers` was never handed to the phone; this is attributed to the simulator link, not demonstrated to be one. Nothing was faked: the phone half is covered by the unit tests only.

### Not verified (needs real devices)

Everything that crosses `WCSession`: background delivery with the phone app closed, the acknowledgement round trip, and the real-world timing of `outstandingUserInfoTransfers`. Also not exercised: a visionOS or macOS build of the app target (the phone sync code is `#if canImport(WatchConnectivity)`).

### Device checklist for B1 (real Watch and iPhone)

1. Finish a match on the Watch with the phone nearby and the phone app open: after Done, the match appears in History within seconds, without leaving the screen, and the Watch has no pending id and no local record (Debug log or debugger).
2. Same with the phone app force-quit: the match is delivered in the background and is in History when the app is opened; the Watch's pending list empties after the acknowledgement arrives (maybe only at its next launch).
3. Finish a match on the Watch while the phone is out of range (or in airplane mode), then reconnect: delivery and acknowledgement happen without any Watch action beyond the next launch or Done.
4. On the match-over screen tap Undo after the deciding point, then replay and Done: the phone gets exactly one match, never the undone one.
5. Delete a synced match on the phone, then make the Watch resend (disconnect before the acknowledgement arrives, then reconnect): the match does not come back.
6. Edit a synced match's players on the phone, then make the Watch resend: the edits are kept.
7. Demo gate: with Pro locked, a synced match counts once toward the demo limit and deleting it does not give the demo match back.
8. Two Watches paired over time, and a reinstall of the phone app: no duplicate rows in History (the same match id collapses), and an old Watch queue still delivers.
9. A phone on an older app version (older schema support): a Watch match is not acknowledged and arrives after the phone app updates.
10. A match being scored on the phone while a Watch match arrives: the live match and its crash recovery are unaffected.

## As built (B1 fixes + gate)

### Review fixes

- **Every outcome is logged.** `WatchMatchReceiver` logs each result with the match id and the reason (never player data) under subsystem `com.delonsampaio.ServerTwo`, category `WatchSync`: imported, duplicate, rejected (reason), id mismatch, newer schema, unreadable payload, a storage failure, and every case where no acknowledgement is sent. The Watch deletes its only copy on an ack, so "why was this not imported" must be answerable afterwards. Both `WCSession` adapters also log a one-line state at events (never polled): activation finished, a transfer queued, `didFinish` (with the error), and a userInfo received. iOS: activation, paired, watch app installed, reachable, outstanding transfers. watchOS: activation, companion installed, reachable, outstanding transfers. `acknowledge` logs when it returns silently (not activated or not paired).
- **A save that throws is rolled back.** `saveCompletedMatch` now calls `rollback()` when its `save()` fails (`rollback()` discards every unsaved change in its context, including the inverse changes `players =` stages on existing saved players, and no delete is ever staged there), so `fetchMatchRecord(id:)` can never find an unsaved record and `savedRecord` never points at one. A failure after the record was stored (clearing the snapshot) keeps the stored record, so a retry cannot duplicate it, and the session remembers that the snapshot (one point short) is still on disk: Done and abandon retry the clear, and at launch `resumeIfNeeded` discards a snapshot whose start time matches an already saved match instead of resuming it (so a relaunch can neither replay, save, count nor send the match twice). Both cases are tested through two seams (`beforeSaveHookForTesting`, `afterSaveHookForTesting`), with the pending id and the demo counter checked.
- **`deleteMatch` deletes every row sharing the id** (a hidden twin from a reinstall plus CloudKit race would otherwise reappear); the id enters the seen set once.
- **An unreadable payload with no `schema` key** is treated as unsupported (not rejected, not acknowledged): it may come from a version this app cannot read. With a known schema it is still rejected and acknowledged.
- **End Match on the match-over screen:** found unreachable. End Match is on the scoring screen only; `WatchFlow` shows the match-over screen (Done, Undo) as soon as the match is decided, so `abandon()` cannot be reached for a saved match through the UI. It is now also safe by itself: `abandon()` on a match that is already saved hands it to sync like Done instead of orphaning its pending record.
- **Tests for the gaps:** a table of real engine matches (side-out, rally, rally with freeze; doubles and singles; to 11, 15 and 21; best of 1, 3 and 5; overtime finals; win by two off) played through `SyncedMatchPayload(record:)` and its JSON into `importSyncedMatch`, all `.imported` (the guard against silent loss; no validator change was needed); a freeze overtime test with a wider margin; a failed local delete on an ack leaves the id pending; an ack for a stale record is ignored.

### Free-demo gate (Watch)

- **Rule:** free is ONE completed match for life, the same limit as the phone (`demoMatchLimit` 1). The Watch may start a match iff `isPro || max(watchLocalCount, phoneReportedCount) < 1`. It is the larger count, not the sum, so a Watch match already imported by the phone counts once. Checked when Start Match is tapped, never mid-match (a live match is never interrupted by a revocation). `-Debug-WatchDemoMatch` bypasses it.
- **Pro on the Watch** is `storeKitPro || phonePro`. StoreKit: `Transaction.currentEntitlements` for `com.delonsampaio.ServerTwo.pro`, verified only and not revoked, through the rule now shared in the kit (`ProEntitlementRule`, also used by the phone's `StoreManager.isProEntitled`; the phone's tests are unchanged and green). Phone: the iPhone pushes `["proUnlocked": Bool, "completedMatchCount": Int]` with `updateApplicationContext` (`PhoneStateContext`) at session activation, when the entitlement changes and whenever a match is counted (`ActiveMatchController.onDemoStateChanged` feeding `PhoneStatePublisher`); the Watch caches it in UserDefaults (`WatchEntitlementCache`) and re-reads the system's last received context at activation, so buying Pro on the phone unlocks the Watch over Bluetooth even if the Watch cannot reach Apple. A phone "not Pro" never overrides a StoreKit "Pro".
- **Counter:** `WatchLifetimeCounter` (UserDefaults, locked, never below 0): +1 when a finished match is saved (`StandaloneMatchSession.saveIfNeeded`, including the recovered post-store failure), -1 when its deciding point is undone, never counted for a failed save or an abandoned match.
- **UI:** Home disables Start Match and shows "Free demo used. Unlock Server Two Pro on your iPhone." when blocked. No purchase UI on the Watch in v1. Checked in the Watch simulator with `-Debug-WatchDemoMatch -Debug-WatchDemoState homeBlocked` (and `home` for the open state), 40 mm SE 3.
- **Structure:** pure types in `PickleballKit/Sources/PickleballKit/Demo/` (`WatchDemoGate`, `WatchLifetimeCounter`, `PhoneStateContext`, `WatchEntitlementCache`, `WatchAccess`, `ProEntitlementRule`, `PhoneStatePublisher`, protocols `WatchEntitlementReading` and `PhoneStatePushing`); the StoreKit read is a thin Watch-target adapter (`WatchStoreKitEntitlements`) behind a protocol with a fake in tests; `PhoneWatchSync.push` is the `updateApplicationContext` call (only when activated and paired, errors logged and ignored).

### Verified

`swift test`: 366 tests pass (326 after the first B1 round). One focused iOS run (`ServerTwoTests`, `PaywallTriggerUITests`, `ProPurchaseUITests`): 389 of 389 pass. Watch Debug and Release and iOS Debug and Release builds, fresh derived data, no project-source warnings. The gate and counter tests were written before the code (RED: the kit tests did not compile without the types; GREEN after).

### Not verified

StoreKit on a real Watch (the simulator has no purchase to read), `updateApplicationContext` delivery between devices (same limitation as the sync: the simulator pair did not carry WatchConnectivity traffic), and the phone's push at activation on a device.

### Device checklist additions

11. Read the new logs in Console (subsystem `com.delonsampaio.ServerTwo`, category `WatchSync`) on both devices: the state lines (activation, paired or companion installed, reachable, outstanding transfers) at activation, when the Watch queues a transfer, in `didFinish` and when the phone receives one. A match that never arrives should show up there as "not activated", "not installed" or a transfer that never finishes.
12. With the phone app backgrounded and the Watch app not running, finish a match: does the phone import it, and does the Watch process the acknowledgement (at its next launch only?). Nothing handles `.backgroundTask(.watchConnectivity)` yet, so an ack may only be processed at the next foreground launch of the Watch app.
13. Delete a synced match on the phone, then have the Watch resend (disconnect before the ack arrives): the log must say "duplicate (already here or seen)" and the match must not come back. Known limits: the seen-id set shares its 500 slots with every phone delete, and deletes made on other CloudKit devices never reach it.
14. Free demo: on a free install with Pro locked, play one match on the Watch: Home then shows "Free demo used..." with Start disabled. Play one on the phone first: the Watch is blocked after the phone's state arrives (and after the watch relaunches, from the cache). Buy Pro on the phone: the Watch unlocks over Bluetooth without the Watch reaching Apple. Check Pro bought with the same Apple ID is seen by StoreKit on the Watch alone (phone off). Refund or revoke: Home re-locks once the phone next pushes (or StoreKit and the cached phone flag both say not Pro), never mid-match; see the known limits below.
15. Undo the deciding point on a free Watch: the demo is given back (Start enabled again after Undo, Done not yet tapped is the only window); replay and Done counts once.

### Known limits of the gate and the review follow-ups (accepted for v1)

- **No staleness policy for the cached phone flag.** With the cached phone flag true and StoreKit now false (a refund), the Watch stays unlocked until the phone app next pushes false; a user who is refunded and then unpairs or deletes the phone app stays Pro on the Watch indefinitely.
- **A free install allows one start until the phone's last context is applied** (it never arrives if the phone never pushed), and a Pro user whose Watch counter is 1 or more, with no cache and no StoreKit result yet, sees "Free demo used" until the phone pushes: the phone app has to be opened once after updating.
- **StoreKit is read once at launch, with no `Transaction.updates` listener on the Watch**: a purchase made while the Watch app is open is seen at the next launch (a purchase made on the phone arrives through the push).
- **Start, undo, End Match loop:** a free user can start a match, play almost to the end and abandon it without it counting, so near-complete free matches are possible. The phone has the same property; accepted.
- **`demoMatchLimit` exists twice** (`WatchDemoGate.demoMatchLimit` in the kit and the phone's `ActiveMatchController.demoMatchLimit`), and taking the larger of the two counts undercounts if the limit is ever raised above 1 (a match played on both devices counts once).
- **State pushes:** the phone skips a push when the state is unchanged since the last one (and when the Watch app is not installed), and forgets that memory at every session activation.
- DEBUG demo launches clear the `WatchDemo` defaults suite first, so the blocked state only shows when asked for.



## Workout (C)

A Gemini review of the first draft was checked against the code and the watchOS 27 SDK headers; its accepted points are folded in below. Rejected: usage strings on the iPhone target (the phone never links HealthKit; add them only if Validate App complains) and its App Review guideline citation (not verified).

### Behaviour

- **One workout per match**, activity type `.pickleball` (available since watchOS 7, verified in `HKWorkoutActivityType.h`), `locationType = .unknown` (no GPS). Starts when the match starts (after the coin flip), runs through game-over screens (rest between games belongs to the match).
- **Lifecycle follows the match, and Undo must keep working.** An ended `HKWorkoutSession`/`HKLiveWorkoutBuilder` can never be reopened, so the workout is *finished only at Done*:
  - deciding point scored: `pause()` (freezes the elapsed time at the match end);
  - Undo of the deciding point: `resume()` (same session and builder continue);
  - Done: add metadata `HKMetadataKeyExternalUUID` = the saved match's id, `end()`, `endCollection(at:)`, `finishWorkout()` (a nil workout with no error is success: it happens when the watch is passcode-locked);
  - End Match (abandon, unsaved): `end()`, `endCollection(at:)`, `discardWorkout()`; discard is never skipped for an unsaved match.
- **Start and stop are serialised** in one async queue (a new start awaits any in-flight finish or discard), so Done then an immediate new match cannot race.
- **Authorization is lazy** at the first match start and never blocks scoring: share = workout type and active energy burned, read = heart rate and active energy burned. Denied or unavailable (`HKHealthStore.isHealthDataAvailable()`, workout share not authorised) means no workout and no error UI; scoring is unchanged. A denied heart-rate read just shows no BPM.
- **Setting:** "Record workout" switch in the Rules sheet (default on, `UserDefaults` key `watchRecordWorkout`). Off: no authorization request and no session.
- **Heart rate:** a small readout (heart symbol and BPM) at the trailing end of the Undo row on the scoring screen, shown only while a rate exists, hidden in Always-On (`isLuminanceReduced`), updated only when the rounded integer changes, never ticked by a timer. No elapsed-time readout (Health shows it) and no extra row, so the 44 pt tap zones keep their height.
- **Failure is silent.** If the session fails or ends externally (for example the user starts Apple's Workout app), the workout state is cleared and scoring continues untouched.
- **Relaunch (`recoverActiveWorkoutSession` at launch, after `resumeIfNeeded`):** recovered session and match active: re-attach delegates and `resume()`; recovered session and no match (killed on the match-over screen): finish it (without metadata) so it still reaches Health; no recovered session: nothing (a match whose workout is gone is not given a new one).
- **Demo and automation launches** (`-Debug-WatchDemoMatch`, `-Debug-WatchAutoSyncMatch`) use a no-op controller, so no Health prompt appears over screenshots; a fake can show the BPM readout for screenshots.

### Architecture

- `PickleballKit`: `MatchLifecycleEvent` (started, decided, reopened, finished(matchID), abandoned) emitted by `StandaloneMatchSession` through one optional hook `onLifecycleEvent` at: `start`, the deciding `recordPoint`, an `undo` that reopens a decided match, a successful `dismissFinishedMatch` / saved-match `abandon` (finished, with the id), and an unsaved `abandon`. `WorkoutBackend` protocol (`@MainActor`; authorize, start, pause, resume, finish(matchID), discard, recover) and `WorkoutController` (`@MainActor @Observable`: `phase`, `heartRate`, the serial queue, the enable switch, the launch reconciliation). Fully unit-tested with a fake backend.
- Watch target: `HealthKitWorkoutBackend` and a `nonisolated` delegate adapter (the module defaults to MainActor and HealthKit calls delegates on a background queue, so every delegate method is `nonisolated` and hops to the main actor with plain values only; no `@unchecked Sendable`, no `@preconcurrency`).
- Target settings: new `ServerTwo Watch App/ServerTwoWatchApp.entitlements` (`com.apple.developer.healthkit` true, `com.apple.developer.healthkit.access` empty array, excluded from the target's resources), `CODE_SIGN_ENTITLEMENTS`, `WKBackgroundModes` = `workout-processing` (required for the app to stay running in a workout), `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`. The iPhone app is unchanged.

### Not verifiable in the simulator

Tap-to-score with a live session, staying frontmost on wrist drop and in Always-On, real heart rate, the system Health permission sheet on a real Watch, recovery after a real kill, and whether the Watch app is accepted by Validate App with HealthKit and no phone-side entitlement. Device checklist for the user is added when built.

## As built (C)

### What was built

- `PickleballKit`: `MatchLifecycleEvent` and `StandaloneMatchSession.onLifecycleEvent` (events as designed above: `decided` is emitted right after the haptic callback and before the save, `finished(matchID:)` before `onFinishedMatchDismissed`), `WorkoutBackend`, `WorkoutController` (`phase` is idle, starting, running, paused or ending; a serial queue where each operation awaits the previous one; the enable switch read when the match starts) and `WorkoutPreference` (key `watchRecordWorkout`, default on). 32 new tests (22 for the controller with a fake backend, 10 for the session hook); the package has 403 tests, all passing.
- Watch target: `HealthKitWorkoutBackend` (`.pickleball`, `.unknown` location, authorization sets as designed, `end()` then `endCollection` then `finishWorkout`, `HKMetadataKeyExternalUUID` before finishing, discard as end, endCollection, discardWorkout, recovery by re-attaching delegates only), a `nonisolated` `WorkoutDelegateAdapter` (only `let` `@Sendable` closures; the heart-rate statistic is read into an `Int` on HealthKit's queue before hopping to the main actor), `NoOpWorkoutBackend` for `-Debug-WatchDemoMatch` and `-Debug-WatchAutoSyncMatch`, all wired in `ServerTwoWatchApp.init` (`recoverAtLaunch` in a `Task` right after `resumeIfNeeded`). No `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency`.
- UI: "Record workout" toggle in the Rules sheet (`@AppStorage`), the heart readout at the trailing end of the Undo row (identifier `HeartRate`, hidden in Always-On and while no rate exists).
- Settings: `ServerTwo Watch App/ServerTwoWatchApp.entitlements` (HealthKit, empty access array) through `CODE_SIGN_ENTITLEMENTS`, both usage strings through `INFOPLIST_KEY_*`, and `WKBackgroundModes` = `workout-processing` through a small `ServerTwo Watch App/Info.plist` fragment merged with the generated one. Both files are excluded from the target's resources by a `PBXFileSystemSynchronizedBuildFileExceptionSet`, like the Live Activity's `Info.plist`.

### Deviations from the design

- **`INFOPLIST_KEY_WKBackgroundModes` does not work**: the key did not land in the built Info.plist (not investigated further). The fragment `Info.plist` (through `INFOPLIST_FILE`) does land, in Debug and Release.
- **Heart rate is cleared while the workout is paused** (the readout is on the scoring screen only, so it never shows at match over, but an Undo no longer shows a stale rate until the next sample).
- **Callbacks carry an identity** (a generation in the controller, an attachment id in the backend) so a late callback from an earlier session cannot stop or feed the next match's workout.

### Verified

`swift test` in `PickleballKit` (403 tests, 0 failures), `plutil -lint` on the project, the entitlements and the Info.plist fragment, `xcodebuild -list`, Debug and Release builds of the Watch scheme (no project-source warnings), and an iOS build of the `ServerTwo` scheme with the embedded `Watch/ServerTwo Watch App.app` (its Info.plist has `WKBackgroundModes`). The built Watch Info.plist (Debug and Release) has both Health usage strings and `workout-processing`. The simulator build is ad-hoc signed: `codesign -d --entitlements -` shows no entitlements, but the entitlements embedded in the executable (`__TEXT,__entitlements`, from the `.xcent`) contain `com.apple.developer.healthkit` and an empty `com.apple.developer.healthkit.access`. The iOS build used the "iPhone 17 Pro iOS 27" simulator: the plain "iPhone 17 Pro" runs iOS 26.5, below the app's deployment target.

### Not verified (nothing was run against real HealthKit)

Everything under "Not verifiable in the simulator" above, plus: that `WKBackgroundModes` with only `workout-processing` is what App Store validation wants, that the provisioning profile (automatic signing) gains the HealthKit capability for `com.delonsampaio.ServerTwo.watchkitapp` at the first device build or archive, that `recoverActiveWorkoutSession` returns the session after a real kill, that `endCollection`/`finishWorkout` after `end()` saves a complete workout (the order is the documented one, not run), the delegate threading under Swift 6 at runtime (it compiles clean; no Health callback ever fired), and how the toggle, the readout and the Undo row look on screen (no screenshot was taken for the readout: nothing in the demo launches produces a heart rate).

### Device checklist (C)

16. First launch with a fresh install: start a match; the Health permission sheet appears at the first match start (not at launch) and asks for workout, active energy and heart rate. Allow all. Scoring is usable under the sheet.
17. During a match the BPM readout appears beside Undo within a few seconds, Undo keeps its width and the zones keep their height at the largest text size and on the 40 mm watch; the readout disappears in Always-On and comes back on wake.
18. Wrist down for a minute mid-game, wake: the app is still frontmost, and the match is where it was (this is what the workout is for).
19. Play a match to the end and tap Done: one "Pickleball" workout in Health on the iPhone, with a duration that ends at the deciding point (not at Done), and the match's id in its metadata if you can inspect it.
20. Undo the deciding point, replay and finish: still a single workout (no pause gap in the duration beyond the time between the two points).
21. End Match mid-game: no workout appears in Health.
22. Deny Health access (or turn the switch off in the Rules sheet): scoring is unchanged, no BPM, no error UI, nothing in Health. With the switch off nothing asks for permission at all.
23. Done then Start Match immediately: the second match gets its own workout and the first is complete in Health.
24. Start Apple's Workout app mid-match: the Server Two workout stops silently, scoring continues, no BPM.
25. Force-quit mid-match and relaunch: the match resumes, the workout resumes (BPM comes back), and finishing it gives one workout. Force-quit on the match-over screen and relaunch: the workout is finished into Health without waiting for another match.
26. Passcode-locked watch at Done: no error, and the workout appears in Health after unlocking.
27. Archive and Validate App with the HealthKit entitlement on the Watch app only (the iPhone app declares none); if validation asks for the usage strings on the iPhone target, add them there.
