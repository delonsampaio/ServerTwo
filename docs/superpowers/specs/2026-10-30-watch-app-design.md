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

_Filled in once the target and screens are built; see the sections below._
