# Live Activity (Lock Screen / Dynamic Island / StandBy) Design

**Goal:** Show the live match score on the Lock Screen, Dynamic Island, and StandBy mode, so a player doesn't have to unlock their phone (or stop it charging on a MagSafe mount courtside) just to check the score.

## Context

Last of four specs from a feature-backlog review, and architecturally the largest and riskiest — confirmed by research, not assumed. Two scope decisions came out of that research and were confirmed with the user directly before any design work:

- **Read-only, not interactive.** The original pitch included "+1 Team A / +1 Team B" buttons directly on the Lock Screen. Researching the actual mechanics first: interactive Live Activity buttons require a `LiveActivityIntent`, and *which process its `perform()` runs in is itself disputed* — developer reports on Apple's own forums describe it running in the main app's process on iOS 17 and moving to the extension's process on iOS 18, with real, documented bugs (stale SwiftData fetches, the main app's in-memory `ModelContext` not picking up the extension's writes without an explicit refetch on scene activation). That's cross-process state synchronization with version-dependent behavior even experienced developers are confused about — not a complexity this app's "fast, frictionless, low-risk utility" positioning should take on for a feature whose core value (seeing the score without unlocking) is fully delivered by a read-only display. Interactive scoring is explicitly deferred, not designed here.
- **New Xcode target added manually, not scripted.** This needs a Widget Extension target that doesn't exist in the project yet. Hand-scripting a new `PBXNativeTarget` into `project.pbxproj` via text edits carries real risk of corrupting the project file — Xcode's own target-creation wizard correctly wires up Info.plist generation, entitlements, the embed-extension build phase, and product dependencies, which would be error-prone to replicate by hand. **This spec assumes the user has already added a Widget Extension target via Xcode (File > New > Target > Widget Extension, with "Include Live Activity" checked if offered) before implementation begins** — everything below describes what goes inside that scaffold and what changes in the main app, not how to create the target itself.

Because of the read-only scoping decision, this also turns out to need **no App Group, no shared SwiftData container, and no `LiveActivityIntent`** — the main app already has the live `PickleballMatch`/`ActiveMatchController` in its own process; it just needs to push updates to the Activity the same way it already pushes crash-recovery snapshots.

## What it shows

**Lock Screen** (and, automatically, StandBy — see below): both team names, their current scores, which team is serving, and (for Best of 3/5) games won. A match-format pill ("Doubles • Best of 3"), matching the style already established on `MatchDetailView`'s summary card.

**Dynamic Island, expanded**: leading region shows Team A's name and score, trailing region shows Team B's, a center or bottom region shows the serving indicator and games-won tally.

**Dynamic Island, compact**: `compactLeading` and `compactTrailing` show each team's score only (names don't fit at this size) — the serving team's score gets a subtle accent, reusing the same visual language `ScoringView`'s own "SERVING" badge already uses.

**Dynamic Island, minimal**: a single small element — just a serving-indicator glyph, since there's no room for two scores and a server indicator at this size.

**StandBy mode**: verified via research, not assumed — this is **mostly automatic**. The system scales the Lock Screen presentation up to fill the screen when the device is charging in landscape; no separate StandBy-specific view is required for a baseline result. For a result that doesn't just look like an oversized phone widget, ActivityKit offers an opt-in `.supplementalActivityFamilies([.medium])` modifier with a dedicated layout for that family — recommended here given this is explicitly the headline use case from the original pitch ("MagSafe mount courtside, giant high-contrast scoreboard"), but the baseline (no supplemental layout) still works and is the fallback if that polish pass doesn't make it into the first implementation.

## Where the shared types live

**Not in `PickleballKit`.** That package declares `.iOS(.v17), .watchOS(.v10), .macOS(.v14)` as supported platforms (`PickleballKit/Package.swift`) — it's genuinely built and tested cross-platform (confirmed by its own existing macOS index-build artifacts). `ActivityKit` doesn't exist on macOS at all; importing it anywhere in that package would break the macOS platform target. This follows the same principle already established twice elsewhere in this codebase — keeping the live engine free of wall-clock time, keeping player identity out of it — extended here to keeping platform-specific frameworks out of a package that's deliberately kept portable.

Instead, a new small file (e.g. `ServerTwo/LiveActivity/PickleballActivityAttributes.swift`) is added to **both** the `ServerTwo` app target's membership and the new widget extension target's — the standard pattern for a type two targets both need, when a shared package isn't the right home for it:

```swift
import ActivityKit

struct PickleballActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var teamAScore: Int
        var teamBScore: Int
        var teamAGamesWon: Int
        var teamBGamesWon: Int
        // String, not `Team` directly — sidesteps any question of
        // whether `Team`'s existing Codable/Sendable conformance (it
        // doesn't declare Hashable explicitly) is sufficient for
        // ActivityKit's `ContentState: Hashable` requirement, by
        // matching this codebase's own established precedent for
        // exactly this kind of serialization boundary: `GameRecord`
        // already stores `winningTeamRawValue: String`, not `Team`,
        // for the same reason.
        var servingTeamRawValue: String
        var isMatchOver: Bool
    }

    let teamAName: String
    let teamBName: String
    let matchFormatSummary: String  // e.g. "Doubles • Best of 3" - precomputed, not recomputed per update
}
```

A small mapping function — pure, easily unit-testable without any ActivityKit involvement — converts the app's live match state into a `ContentState`:

```swift
extension PickleballActivityAttributes.ContentState {
    init(match: PickleballMatch) {
        let state = match.currentGame.state
        self.teamAScore = state.teamAScore
        self.teamBScore = state.teamBScore
        self.teamAGamesWon = match.gamesWon(for: .teamA)
        self.teamBGamesWon = match.gamesWon(for: .teamB)
        self.servingTeamRawValue = state.servingTeam.rawValue
        self.isMatchOver = match.isMatchOver
    }
}
```

## Extracting the format-summary logic

`matchFormatSummary` ("Doubles • Best of 3") needs the same mode/best-of/scoring-format text `MatchDetailView.formatSummary` already computes — but that's a private computed property on a View, and it works from a *decoded* `GameConfiguration` (`try? JSONDecoder().decode(GameConfiguration.self, from: match.configurationData)`), not the live, already-native `GameConfiguration` `ActiveMatchController` holds directly. Rather than duplicate the mode/best-of/suffix logic a second time with a different input shape, it's extracted into `PickleballKit` as a pure function both call — the same kind of small, justified extraction the Quick Log spec made for `isCompletedGameScore`:

```swift
extension GameConfiguration {
    /// "Doubles • Best of 3" / "Singles • Best of 1 • Rally" etc.
    public func summaryText(matchFormat: MatchFormat) -> String {
        let mode = playMode == .singles ? "Singles" : "Doubles"
        let bestOf = "Best of \(matchFormat.rawValue)"
        switch scoringFormat {
        case .sideOut: return "\(mode) • \(bestOf)"
        case .rally: return "\(mode) • \(bestOf) • Rally"
        }
    }
}
```

`MatchDetailView.formatSummary` becomes `configuration.summaryText(matchFormat: match.matchFormat)` after its existing decode (no behavior change — same decode, same fallback to `nil` on failure, just the formatting logic moved). `ActiveMatchController` calls `info.match.configuration.summaryText(matchFormat: info.match.matchFormat)` directly, no decode needed, since it already holds the live value.

## Starting, updating, and ending the Activity

All three hook into `ActiveMatchController`'s existing structure, at the same points `persistSnapshot()` already runs — no new observation mechanism needed, consistent with how the Chemistry/Game Duration and Doubles L/R specs both reused these same three wrapper methods for their own per-point bookkeeping.

**Start**, inside `confirmFirstServe` (right where `persistSnapshot()` is already called after creating the live match):

```swift
private func startLiveActivity(info: ActiveMatchInfo) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let attributes = PickleballActivityAttributes(
        teamAName: info.teamAName,
        teamBName: info.teamBName,
        matchFormatSummary: info.match.configuration.summaryText(matchFormat: info.match.matchFormat)
    )
    let content = ActivityContent(
        state: PickleballActivityAttributes.ContentState(match: info.match),
        staleDate: nil
    )
    currentActivity = try? Activity.request(attributes: attributes, content: content)
}
```

`ActivityAuthorizationInfo().areActivitiesEnabled` is checked and silently no-op'd on `false` (the user disabled Live Activities in Settings) — this is a nice-to-have enhancement layered on top of an app that works completely fine without it, the same resilience posture most of this codebase's `try?`-guarded side effects already take, not a feature the match-scoring flow can ever block on.

**Update**, inside `recordPoint`, `undo`, and `correctScore` — alongside their existing `persistSnapshot()` call:

```swift
private func updateLiveActivity(info: ActiveMatchInfo) {
    guard let currentActivity else { return }
    Task {
        await currentActivity.update(
            ActivityContent(state: .init(match: info.match), staleDate: nil)
        )
    }
}
```

**End**, inside `finishMatch()` and `cancelActiveMatch()`:

```swift
private func endLiveActivity() {
    guard let currentActivity else { return }
    Task {
        await currentActivity.end(nil, dismissalPolicy: .immediate)
    }
    self.currentActivity = nil
}
```

**Resume** (`resumeIfNeeded`, after a crash/relaunch): Live Activities are managed by the system, independent of the app's own process — a crash doesn't necessarily kill a running Activity. Before starting a new one, check for an existing one first. Called right after `resumeIfNeeded` constructs its `ActiveMatchInfo` (the same `info` `startLiveActivity`/`updateLiveActivity` already take, so this slots into the existing method without a new parameter shape):

```swift
private func resumeLiveActivityIfNeeded(info: ActiveMatchInfo) {
    if let existing = Activity<PickleballActivityAttributes>.activities.first {
        currentActivity = existing
        updateLiveActivity(info: info)
    } else {
        startLiveActivity(info: info)
    }
}
```

`currentActivity: Activity<PickleballActivityAttributes>?` is a new, non-persisted property on `ActiveMatchController` — it doesn't need to survive a relaunch itself (the code above re-discovers it from the system on resume), so it's the same category of live-only state as the Doubles L/R spec's swap-toggle booleans, not something written to `GameRecord`/`MatchRecord`.

## Entitlement

`INFOPLIST_KEY_NSSupportsLiveActivities = YES` added to the `ServerTwo` app target's Debug and Release build settings — the exact same mechanism, and the exact same two call sites (`project.pbxproj`'s app-target Debug/Release configurations), as the `INFOPLIST_KEY_UIBackgroundModes` fix already applied for CloudKit earlier in this session.

## Testing

**What's actually testable, and what isn't — stated plainly rather than overclaimed.** There's no XCTest API for asserting what's rendered inside a Live Activity or Dynamic Island; UI tests cannot inspect that content. What *is* testable without any ActivityKit involvement:

- Unit tests on `PickleballActivityAttributes.ContentState.init(match:)` — a pure mapping function — covering: scores reflect `currentGame.state`; games-won reflects `match.gamesWon(for:)` for Best of 3/5; `isMatchOver` flips correctly; `servingTeamRawValue` matches `state.servingTeam.rawValue`.
- A test confirming `ActiveMatchController` gracefully no-ops its Live Activity calls (doesn't throw, doesn't crash) when `ActivityAuthorizationInfo().areActivitiesEnabled` is `false` — simulating the user having disabled Live Activities.
- Manual, on-device or simulator verification (screenshot-based, the same empirical standard this session has held for every other visual feature) of the actual Lock Screen, all three Dynamic Island presentations, and StandBy appearance — this cannot be automated, and the spec doesn't pretend otherwise.

## Non-goals

- No interactive Lock Screen scoring buttons — see Context above. A future spec, if pursued, would need its own research into the current (not two-OS-versions-stale) `LiveActivityIntent` process-location behavior before any design commitment.
- No push-notification-driven remote updates (`pushType` is passed as implicit `nil`/local-only in `Activity.request`) — this app has no backend, consistent with its established zero-custom-backend architecture; all updates originate from the app's own live scoring session, never a server.
- No Apple Watch or CarPlay presentation (`supplementalActivityFamilies([.small])`) — StandBy's `.medium` family is the one explicitly motivated by the original pitch; Watch/CarPlay support isn't requested and isn't designed here.
