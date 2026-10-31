# Watch App Design

**Goal:** A standalone Apple Watch app that keeps score of a pickleball match at the court with one hand, with no iPhone nearby. This is Phase 5 of the main spec (`2026-10-06-server-two-design.md`, "Watch app", 3.4 Sync, 3.5 Platform points), split into three sub-projects so each ships and is verified on its own.

## Sub-projects

- **A (this spec, built):** the watchOS app target, a platform-neutral match session in `PickleballKit`, a local-only store, and the scoring screens. The Watch scores a whole match on its own and saves the finished match locally.
- **B (not built):** WatchConnectivity queue of finished matches to the phone. The Watch sends the matches in its pending-sync set (below) with `transferUserInfo`; the phone saves each into its CloudKit store and dedupes by match UUID (`MatchRecord.id`), then acknowledges so the Watch calls `confirmSynced`. Also decides how the phone's Pro entitlement reaches the Watch: StoreKit `currentEntitlements` on the Watch and a per-device demo counter, handled together with B because both need the phone link.
- **C (not built):** `HKWorkoutSession` (pickleball workout) so watchOS keeps the app foregrounded during a match and logs a workout, heart rate on the scoring screen, and the Health permission. No HealthKit entitlement or usage string exists in the target until C.
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

- **`PickleballKit`:** `StandaloneMatchSession`, `LastUsedRules`, `PendingSyncStore`, `PersistenceContainer.makeLocalOnlyContainer(isStoredInMemoryOnly:)`, and the shared `MatchFormat.isLastGame(index:)`, `SideSwitchDirection`, `SideSwitchPromptTracker` (public). 43 new tests (252 in the package, 209 before), all `swift test`, written test first; the kit also builds for watchOS Simulator. The iOS app lost `MatchFormat+LastGame.swift` and `SideSwitchPromptTracker.swift` and uses the kit versions (`ScoringPrompt.SideSwitchDirection` is now a typealias of the kit type, so its call sites and tests are unchanged).
- **`ServerTwo Watch App` target**, folder `ServerTwo Watch App/`: `ServerTwoWatchApp` (container, session, resume at launch), `WatchRootView` (screen chosen from the session state), `HomeView` + `RulesSheet`, `CoinFlipView`, `ScoringView` (zones, Undo, End match, side-switch notice), `GameOverView`, `MatchOverView`, `WatchHaptics`, and a DEBUG-only `WatchDemo` (`-Debug-WatchDemoMatch [-Debug-WatchDemoState scoringB|gameOver|matchOver|sideSwitch|coinFlip]`, in-memory store, throwaway defaults suite) used for the simulator screenshots.
- **Colours:** the watch catalog holds the app's `AccentColor`, `AccentText` and `SecondaryText` with only their DARK values as the single appearance. watchOS has no light appearance and picks the catalog's default entry, which rendered the light-mode secondary grey (#5C5C61) on black; no new colour values were introduced. The app icon slot is empty but valid.
- **Dynamic type:** the zone text is capped at xLarge (a zone is a fixed-height surface) and scales down to half size rather than clipping; the system chrome (title, Undo) follows the user's size; VoiceOver reads full labels ("Team A, 7 points, serving, server 2").

### How the target was added

The `xcodeproj` gem cannot write file-system-synchronized projects (objectVersion 90), so `project.pbxproj` was edited by hand, following the Live Activity extension commit. The change is 158 added lines and no removed lines:

- a native target `ServerTwo Watch App` (`com.apple.product-type.application`, `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `TARGETED_DEVICE_FAMILY = 4`, `WATCHOS_DEPLOYMENT_TARGET = 10.0` to match the package's `.watchOS(.v10)`, `SKIP_INSTALL = YES`), bundle id `com.delonsampaio.ServerTwo.watchkitapp`, generated Info.plist with `WKApplication`, `WKCompanionAppBundleIdentifier = com.delonsampaio.ServerTwo` and `WKRunsIndependentlyOfCompanionApp`, same team, automatic signing and Swift 6 settings as the app;
- its own synchronized root group, a Frameworks phase with a second `PickleballKit` package product dependency and build file (the pattern the app and the tests use);
- an "Embed Watch Content" copy phase on the iOS app (`dstSubfolderSpec = 16`, `dstPath = $(CONTENTS_FOLDER_PATH)/Watch`), a target dependency, and `platformFilter = ios` on both so the app's macOS and visionOS destinations do not try to embed it.

The tests' targets and the Live Activity target are untouched. No HealthKit or other entitlement or usage string was added.

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
