# Phase 3: iOS App UI — Design Spec

Date: 2026-10-07
Status: Approved for implementation planning
Parent spec: docs/superpowers/specs/2026-10-06-server-two-design.md (Phase 3 scope, §4)

## 1. Scope

This phase builds the `ServerTwo` iOS app's UI: new-match setup, scoring,
onboarding, match history/stats, a shareable match-recap card, a settings
shell, and a stub paywall. It is pure SwiftUI consuming the already-merged
`PickleballKit` package (`PickleballGame`, `PickleballMatch`,
`MatchRepository`, and the SwiftData history/in-progress models) — this
phase makes **no changes to `PickleballKit` itself**.

Out of scope (explicitly deferred to later phases per the parent spec):
real StoreKit purchase/restore (Phase 4 — Phase 3 ships a stub paywall that
flips a mock `proUnlocked` flag), Watch app (Phase 5), Live Activity /
Dynamic Island (Phase 6), voice announcer audio implementation and
VoiceOver/Dynamic Type audit beyond baseline accessibility labels (Phase
7 — Phase 3 wires the Settings toggle but the announcer itself is a later
phase's work), App Store release prep (Phase 8).

## 2. Architecture

### 2.1 App target structure

- `MyApp.swift` — app entry point. Creates the one `ModelContainer` via
  `PersistenceContainer.makeContainer()` and injects it with
  `.modelContainer(container)` so every view can read
  `@Environment(\.modelContext)`. Shows `OnboardingView` on first launch,
  gated by `@AppStorage("hasSeenOnboarding")`; otherwise shows
  `RootTabView`.
- `ActiveMatchController` — an `@Observable`, `@MainActor` class, the one
  piece of app-level state. Responsibilities:
  - Holds the live `PickleballMatch?`.
  - Builds a `MatchRepository` from the injected `ModelContext`.
  - On launch, calls `MatchRepository.loadInProgressMatch(proUnlocked:demoPointCap:)`
    to recover a crashed/backgrounded match; if one exists, adopts it as
    the live match so `RootTabView`'s Play tab shows `ScoringView`
    directly instead of `MatchSetupView`.
  - After every `recordPoint`/`undo`/`correctScore` call on the live
    match, calls `saveInProgressSnapshot(for:startedAt:)`.
  - When the live match's `isMatchOver` becomes true and the user
    confirms/finishes, calls `saveCompletedMatch(...)`, then clears the
    live match (back to `nil`, so Play tab reverts to `MatchSetupView`).
  - Holds the mock entitlement: `@AppStorage("mockProUnlocked") var proUnlocked: Bool = false`
    and a fixed `let demoPointCap = 5` (per the parent spec's demo cap),
    passed into every `PickleballMatch`/`loadInProgressMatch` call. Phase
    4 replaces this stored property's source with real StoreKit state;
    nothing else in this phase's code changes when that happens, because
    `PickleballMatch`'s constructor already takes these as injected
    parameters (Phase 1's single-enforcement-point design).
  - `@MainActor` is deliberate: this is the first real UI call site for
    `PickleballMatch`/`MatchRepository`, so isolation is chosen to match
    actual call-site concurrency (all SwiftUI view code runs on the main
    actor) rather than guessed in advance — resolving Phase 2's final
    review's deferred Minor #15.
- `RootTabView` — a `TabView` with three tabs: **Play**, **History**,
  **Settings**. Each wraps its content in its own `NavigationStack`.
- No view-model layer beyond `ActiveMatchController`.
  `PickleballMatch`/`PickleballGame` are already `@Observable`; views bind
  to them directly. An extra wrapping layer would be pure indirection.

### 2.2 File layout

```
ServerTwo/
  MyApp.swift                          (modify)
  ActiveMatchController.swift
  Root/
    RootTabView.swift
  Onboarding/
    OnboardingView.swift
  Setup/
    MatchSetupView.swift
  Scoring/
    ScoringView.swift
    CourtDiagramView.swift
    ScoreCorrectionSheet.swift
    TimeoutControlsView.swift
  Paywall/
    PaywallView.swift
  History/
    MatchHistoryListView.swift
    MatchDetailView.swift
    StatsSummaryView.swift
  Share/
    MatchRecapCardView.swift
  Settings/
    SettingsView.swift
    AppSettings.swift                  (AppStorage-backed settings model)
```

`ContentView.swift` (the default template file) is deleted — its one
remaining consumer, the default `WindowGroup`, now shows `RootTabView` via
the modified `MyApp.swift`.

## 3. Screens & Flows

### 3.1 Onboarding

A one-time, paged (`TabView(.page)`-style) modal sequence of 2-3 screens
shown automatically the first time the app launches, explaining the
Server-2 first-game rule (why the very first game of a match starts at
Server 2, not Server 1) in plain language with a simple diagram. Never
shown automatically again once `hasSeenOnboarding` is set. Also reachable
on demand from Settings ("How Scoring Works") using the exact same view,
presented as a sheet.

### 3.2 Match Setup (`MatchSetupView`)

A single scrollable form (not a multi-step wizard), grouped into sections:

1. **Mode** — Singles / Doubles picker.
2. **Scoring format** — Side-out / Rally picker; if Rally, a "Freeze"
   sub-toggle (win-game-point-on-serve-only vs. win-on-any-point).
3. **Win score** — 11 / 15 / 21 picker, plus a win-by-2 toggle.
4. **Match format** — Best of 1 / 3 / 5 picker.
5. **Team / player names** — text fields (2 for singles, 4 for doubles,
   grouped into Team A / Team B).
6. **First serve** — a "Flip Coin" button that calls `PickleballKit`'s
   coin-flip utility and displays the result (which team/side serves
   first), required before "Start Match" enables.

"Start Match" builds a `GameConfiguration` + `MatchFormat` from the form's
values, constructs a `PickleballMatch` with them plus
`ActiveMatchController`'s current `proUnlocked`/`demoPointCap`, hands it
to `ActiveMatchController`, and the Play tab's `NavigationStack` pushes to
`ScoringView`.

### 3.3 Scoring (`ScoringView`)

The core screen, built around two large left/right tap zones — the full
available height, split evenly, one per team, each showing that team's
current score as the dominant element. Tapping anywhere in a team's zone
calls `ActiveMatchController`'s record-point path for that team. Large
forgiving tap targets by design, for courtside use with sweaty or gloved
hands.

Layered on top of the two zones:
- **Court diagram** (`CourtDiagramView`) — a small schematic two-box
  court near the top, with a marker showing the serving team and which
  side (left/right) they're on. The diagram itself carries a single
  `accessibilityLabel` describing the same information in words (e.g.
  "Team A serving, right side") — satisfying the parent spec's
  accessibility rule ("nothing is color/visual-only") even though the
  on-screen presentation is diagram-only, per your choice not to show a
  separate visible text label.
- **Side-switch alert** — a banner/toast shown when the game crosses its
  configured side-switch threshold (6/8/11 depending on win score),
  dismissed by the user or automatically after a few seconds.
- **Timeout controls** (`TimeoutControlsView`) — a small button per team,
  disabled once that team's timeout(s) for the game are used.
- **Undo button** — always visible (e.g. toolbar), calls
  `ActiveMatchController`'s undo path.
- **Score correction** — long-press on either team's score number opens
  `ScoreCorrectionSheet`, a small sheet with a stepper/text field to set
  that team's score directly, calling `correctScore(team:to:)`.
- **Paywall trigger** — a `.sheet(isPresented:)` bound to
  `match.isPaywalled`, presenting `PaywallView` when the demo cap is hit.
- **Match end** — when `isMatchOver` becomes true, the tap zones disable
  and a "Finish Match" confirmation (showing the final score) appears;
  confirming calls `ActiveMatchController`'s finish path
  (`saveCompletedMatch`) and returns to `MatchSetupView`.

### 3.4 Paywall (`PaywallView`, stub)

A simple sheet explaining the 5-point demo cap and the $1.99 unlock, one
"Unlock Pro" button that sets `ActiveMatchController.proUnlocked = true`
(mock — Phase 4 replaces this button's action with a real StoreKit
purchase flow; nothing else about this view changes), and a visibly
disabled/placeholder "Restore Purchases" row.

### 3.5 History (`MatchHistoryListView` → `MatchDetailView`)

- **List** — matches from `MatchRepository.fetchMatchHistory()`, newest
  first, each row showing team names, final game score, and date. A
  `StatsSummaryView` header above the list shows aggregate win/loss
  record and total points for/against, computed by folding over the
  fetched `[MatchRecord]` — no new persisted aggregate, no new
  `PickleballKit` API.
- **Detail** (`MatchDetailView`) — for a selected match: game-by-game
  final scores, and each game's point-by-point log via
  `GameRecord.orderedPoints` (never raw `.points`, per Phase 2's
  documented ordering trap). A "Share" button generates the recap card.

### 3.6 Share recap card (`MatchRecapCardView`)

A card-shaped SwiftUI view (final score, team/player names, a win
indicator, small Server Two watermark), rendered off-screen via
`ImageRenderer` into a `UIImage`, shared through the standard
`ShareLink`/share-sheet. No per-game breakdown in this version, per your
choice — just the final result.

### 3.7 Settings (`SettingsView`)

- Voice announcer toggle (`AppSettings.voiceAnnouncerEnabled`) — wires the
  toggle and persists it; the announcer's actual audio implementation is
  Phase 7's work, so this phase's toggle has no audible effect yet.
- Haptics toggle (`AppSettings.hapticsEnabled`) — same: persisted here,
  wired into actual haptic calls where those are added (scoring taps,
  etc.) as part of this phase's `ScoringView` work, since haptic feedback
  on every point is simple enough not to defer.
- Theme — Light / Dark / System picker
  (`AppSettings.theme: ColorSchemePreference`), applied via
  `.preferredColorScheme` at the root view.
- "How Scoring Works" — re-presents `OnboardingView` as a sheet.
- About/version row (static, from the app's bundle version).

`AppSettings` is a small `@Observable` class wrapping three
`@AppStorage`-backed properties — not a new SwiftData model; these are
pure UI preferences, not match data, and don't need CloudKit sync.

## 4. Testing

- **Unit tests (`ActiveMatchController`)** — against an in-memory
  `PersistenceContainer` (reusing Phase 2's `makeInMemoryContainer()`):
  construct a match, record points, confirm `saveInProgressSnapshot` is
  called after each (assert via a re-fetch, not a mock — consistent with
  this codebase's established pattern of testing through the real
  SwiftData store rather than mocking it); finish a match and confirm it
  moves from "in-progress" to "completed history" and the live match
  resets to `nil`; construct a fresh controller against a store with a
  saved in-progress snapshot and confirm it resumes rather than starting
  fresh.
- **XCUITest — golden path**: launch → dismiss onboarding → start a new
  match (singles, side-out, win score 11, best-of-1) → tap the Team A
  zone 11 times → confirm the finish screen appears with an 11-0 result →
  confirm the match → go to History → confirm the match appears with the
  correct score.
- **XCUITest — paywall trigger**: launch with a test launch-argument that
  forces `proUnlocked = false` and overrides `demoPointCap` to a small
  number (so the test doesn't need 11 real taps) → tap up to the cap →
  confirm the paywall sheet appears → tap "Unlock Pro" → confirm scoring
  continues past the cap.
- Engine/scoring correctness itself is NOT re-tested here — `PickleballKit`
  already has 85 passing unit tests covering every rule. Phase 3's tests
  exist to catch UI-wiring and persistence-call-site regressions only.

## 5. Open Risks / Things to Verify During Implementation

- `ImageRenderer`'s exact behavior/fidelity for the share card should be
  spot-checked on a real device, not just the simulator, before Phase 3 is
  considered done — text rendering in off-screen `ImageRenderer` captures
  has historically had minor simulator/device differences.
- The XCUITest launch-argument mechanism for overriding `demoPointCap` in
  a test build needs a small, explicit seam in `MyApp.swift` (e.g. reading
  `ProcessInfo.processInfo.arguments` for a test flag) — this is new
  surface this phase introduces and should be kept minimal and clearly
  commented as test-only.
