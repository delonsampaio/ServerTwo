# Server Two: Pickleball Tracker — Design Spec

Date: 2026-10-06
Status: Approved for implementation planning

## 1. Product Vision

Server Two is an iOS + watchOS pickleball scorekeeping app. It owns the game's
genuinely tricky rules (doubles Server 1/Server 2 rotation, side-outs, side
switches) so players don't have to think about them, and it works the way
players actually use a phone or watch courtside: one hand, sun glare, sweat,
sometimes with the phone left in a bag.

Monetization: one-time $1.99 "Pro Unlock" (StoreKit 2 non-consumable). The
free version is feature-complete but caps every game at 5 points so it can
never be finished; purchasing removes the cap permanently. There is exactly
one gate, enforced once, in the shared engine — not scattered across
features — so it can't be bypassed via the standalone Watch app and so the
test matrix stays small.

## 2. Feature Set

### V1 (free demo = full feature set, capped at 5 pts/game; $1.99 removes the cap)

**Engine / rules**
- Doubles and singles
- Side-out scoring and rally scoring (with a "freeze" sub-toggle for rally
  scoring: win-game-point-on-serve-only vs. win on any point)
- Configurable win score (11 / 15 / 21) with win-by-2 toggle
- Best-of-1 / best-of-3 / best-of-5 matches
- Side-switch alerts at the standard thresholds (6 for games to 11, 8 for
  games to 15, 11 for games to 21)
- Timeout tracking per team
- Coin-flip first-serve / first-side picker
- Custom team/player names
- Full undo via a state-history stack
- Manual score correction for disputes
- Demo point-cap enforcement hook (`proUnlocked` + `demoPointCap`)

**Persistence**
- SwiftData local store; CloudKit sync for **completed matches only**
- Auto-saved in-progress game state for crash/force-quit recovery
  (local-only, never synced — see Section 3.3)
- Match history with point-by-point log
- Win/loss and points-for/against stats

**iOS app**
- New-match setup flow (mode, scoring format, win score, best-of-N, names,
  coin flip)
- Scoring screen: score display, serve-side court indicator, side-switch
  alert, timeout controls, undo button, manual correction entry
- Onboarding explaining the Server-2 first-game rule
- Match history / stats browser
- Shareable match-recap image card (`ImageRenderer`) for social sharing
- Settings: voice announcer, haptics, theme
- Paywall screen (triggered at the demo cap) + Restore Purchases

**Watch app**
- Fully standalone: own engine instance + local store, works without the
  iPhone nearby
- `HKWorkoutSession` (`.pickleball`) started with each game, so watchOS
  doesn't suspend/dim the app mid-match and so a workout is logged
- High-contrast, large-tap scoring UI; exact left/right-vs-top/bottom split
  to be decided during the Watch UI phase
- Haptic feedback on every point
- Dedicated Undo button (not a swipe gesture — swipe-from-edge competes with
  the watchOS Control Center system gesture); optional long-press accelerator
- Digital Crown as an alternate scoring input (sweaty/gloved fingers)
- WatchConnectivity live relay to the iPhone when both are reachable

**Live Activity / Dynamic Island**
- `PickleballMatchAttributes`: static team names; dynamic score, server,
  side-switch flag
- Compact / expanded / minimal Dynamic Island presentations
- iPhone owns the Activity (Live Activities are iOS-only); Watch relays
  score changes to the iPhone when reachable

**Audio**
- AVSpeechSynthesizer voice announcer, toggled in settings
- Runs on whichever device is actively being used (Watch or iPhone);
  auto-prefers connected AirPods via standard `AVAudioSession` routing
  rather than defaulting to a phone speaker that may be in a bag

**Accessibility**
- VoiceOver labels on all custom controls
- Dynamic Type support on iPhone UI
- Redundant haptic + visual + audio feedback — nothing is color-only

### Backlog (explicitly deferred, not forgotten)
- Tournament / round-robin bracket mode
- Siri / App Intents shortcuts
- Apple Watch face complications
- iPad-optimized layout
- Localization beyond English
- Double Tap gesture support (watchOS accessibility gesture)
- Alternate / colorblind-safe visual themes
- Manual "stacking" position override (beyond the score-parity-derived
  serve-side indicator already in V1)
- Automated TestFlight/App Store deploy pipeline (fastlane)

## 3. Architecture & Data Model

### 3.1 Targets
- `PickleballKit` — local Swift Package. Engine, SwiftData models, sync
  logic. No UI imports. Shared by all targets below.
- `ServerTwo` (iOS app) — SwiftUI, StoreKit 2, AVSpeechSynthesizer, onboarding.
- `ServerTwo Watch App` (watchOS) — SwiftUI, HealthKit, WatchConnectivity.
- `ServerTwo Widget` (new Widget Extension target) — ActivityKit Live Activity.
- A shared **App Group** across all targets, used to read the Pro-unlock
  entitlement flag from any target (the demo cap must be enforced
  identically everywhere, including a standalone Watch).

### 3.2 Core engine (`PickleballKit`, pure Swift, `@Observable`)
- `PickleballGame` — one game's live state: scores, `Server` (team + 1-or-2),
  scoring format (side-out/rally + freeze flag), win target + win-by-2,
  side-switch thresholds, timeout counts. `recordPoint(for:)`, `undo()`,
  `correctScore(team:to:)`, backed by a state-history stack.
- `PickleballMatch` — wraps 1/3/5 `PickleballGame`s into a best-of-N match,
  tracks games won per team, advances games automatically.
- Takes injected `proUnlocked: Bool` + `demoPointCap: Int?`. When capped and
  unpurchased, `recordPoint` stops advancing past the cap and surfaces a
  paywall signal. This is the single enforcement point.
- Zero persistence/UI knowledge — the primary TDD target.

### 3.3 Persistence (SwiftData, in `PickleballKit`)
- `MatchRecord` / `GameRecord` / `PointEvent` / `TeamSide` — completed-match
  history. Synced via CloudKit.
- `InProgressGameState` — crash-recovery snapshot of the currently-live
  game. **Local-only, excluded from the CloudKit schema.** This is the
  concrete rule that prevents cross-device merge races: an in-progress game
  never leaves the device that's playing it.

### 3.4 Sync & communication
- **Live play, both devices reachable:** WatchConnectivity relays
  point-by-point in real time. One device is the authoritative owner of the
  in-progress game at a time.
- **Live play, Watch standalone:** Watch owns `PickleballGame` +
  `InProgressGameState` locally; nothing leaves the device until the match
  ends.
- **Match completion only:** the owning device writes a `MatchRecord` (+
  children) to SwiftData; CloudKit syncs it in the background. This is the
  *only* data that crosses the CloudKit boundary.

### 3.5 Platform integration points
- **StoreKit 2** (`StoreManager`, iOS target): purchase/restore writes the
  App Group entitlement flag so Watch and Widget see it too.
- **HealthKit** (Watch target): `HKWorkoutSession` (`.pickleball`) started
  per game, ended at match completion or abandonment; elapsed time/heart
  rate surfaced on the scoring screen.
- **ActivityKit** (Widget target): `PickleballMatchAttributes` updated by
  whichever device drives the iPhone's Live Activity.
- **AVFoundation**: voice announcer on the active device, AirPods-preferred
  routing via `AVAudioSession`.

## 4. Build Phases

Each phase is its own spec → plan → implementation cycle. Order matters —
later phases depend on Phase 1 being correct.

0. **Scaffolding** — add Watch App + Widget Extension targets, create
   `PickleballKit` package, configure App Group + CloudKit container,
   replace the placeholder bundle ID, stand up GitHub Actions CI (build on PR).
1. **Core engine** (TDD) — full rules implementation in `PickleballKit`,
   exhaustive unit tests.
2. **Persistence** — SwiftData models, CloudKit schema (completed matches
   only), repository layer, in-memory-container integration tests.
3. **iOS app UI** — setup flow, scoring screen, onboarding, history/stats,
   share-recap card, settings shell. XCUITest for critical flows.
4. **Monetization** — `StoreManager`, paywall, Restore Purchases,
   StoreKit-Configuration-file-driven automated tests.
5. **Watch app** — standalone engine/store, `HKWorkoutSession`,
   high-contrast UI, haptics, dedicated Undo button, Digital Crown input,
   WatchConnectivity relay. Manual QA checklist for gesture/haptic feel.
6. **Live Activity / Dynamic Island** — Widget extension, ActivityKit
   lifecycle, compact/expanded/minimal layouts. Manual QA checklist.
7. **Audio & accessibility** — voice announcer routing, VoiceOver labels,
   Dynamic Type audit.
8. **Release prep** — regression pass, App Store metadata/screenshots,
   privacy manifest, TestFlight.

## 5. Testing & SDLC Strategy

- **TDD for the engine (Phase 1):** failing tests first for every rule —
  first-game Server-2 start, rotation correctness across simulated rally
  sequences, win-by-2 edge cases, best-of-N progression, undo correctness
  (including across game boundaries), side-switch triggers per win-score
  config. Near-exhaustive coverage here — a scoring bug undermines the
  app's entire reason to exist.
- **Integration tests (Phase 2):** SwiftData repository tests against an
  in-memory `ModelContainer` — no real CloudKit calls in CI.
- **UI tests (Phase 3):** XCUITest for the golden path (start match → score
  → finish → appears in history) and the paywall trigger at the demo cap.
- **StoreKit tests (Phase 4):** local StoreKit Configuration file +
  `StoreKitTest` framework to automate purchase/restore without hitting
  sandbox servers.
- **Manual QA checklists (Phases 5-6):** Watch gesture/haptic feel,
  `HKWorkoutSession` behavior, and Live Activity/Dynamic Island rendering
  aren't practically unit-testable — run from a written checklist on
  physical devices before each release.
- **CI (GitHub Actions):** on every PR, run `xcodebuild test` for the
  engine/persistence test targets and the iOS UI test target on a
  simulator. Watch/Widget targets are build-checked only.
- **Git workflow:** `origin` is already GitHub (`delonsampaio/ServerTwo`).
  One feature branch + PR per phase; CI must pass before merging to `main`.

## 6. Open Risks / Things to Verify During Implementation

- Confirm `HKWorkoutActivityType.pickleball` and `AVSpeechSynthesizer`
  watchOS availability against the current SDK (Xcode 27) when Phases 1/5/7
  are implemented.
- The exact rally-scoring "freeze" rule citation from external research is
  unverified — the toggle is being built regardless of which rule year is
  currently "official," and no specific rule-history claim should appear in
  in-app copy without separate verification.
- Left/right vs. top/bottom Watch score-zone layout is an open UX question
  to resolve during the Phase 5 design pass, not before.
