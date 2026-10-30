# Live Activity (Lock Screen / Dynamic Island / StandBy) Design

**Goal:** Show the live match score on the Lock Screen, Dynamic Island, and StandBy mode, so a player doesn't have to unlock their phone (or stop it charging on a MagSafe mount courtside) just to check the score.

## Context

Last of four specs from a feature-backlog review, and architecturally the largest and riskiest — confirmed by research, not assumed. Two scope decisions came out of that research and were confirmed with the user directly before any design work:

- **Read-only, not interactive.** The original pitch included "+1 Team A / +1 Team B" buttons directly on the Lock Screen. Researching the actual mechanics first: interactive Live Activity buttons require a `LiveActivityIntent`, and *which process its `perform()` runs in is itself disputed* — developer reports on Apple's own forums describe it running in the main app's process on iOS 17 and moving to the extension's process on iOS 18, with real, documented bugs (stale SwiftData fetches, the main app's in-memory `ModelContext` not picking up the extension's writes without an explicit refetch on scene activation). One external review of this spec offered a more specific explanation — that `LiveActivityIntent` is designed to run in the main app's process by default, and the forum reports of extension-process execution are a target-membership artifact (the intent type only added to the extension target) or a fully-terminated-app edge case. That's a plausible account, but it isn't independently verified here the way the rest of this spec's claims are, so it's noted as a hypothesis, not folded in as settled fact. **What *is* independently verified:** even granting the more favorable reading, `ActiveMatchController` is held in `@State` at the `MyApp` struct level (`_activeMatchController = State(initialValue: ActiveMatchController(...))`, confirmed directly in `MyApp.swift`) — there is no existing global or singleton accessor an `AppIntent.perform()` running outside the SwiftUI view hierarchy could reach it through, regardless of which process it runs in. Combined with the accidental-tap risk of a live scoring button sitting unguarded on the Lock Screen during a fast-paced game, read-only is the right call on multiple independent grounds, not just the disputed one. Interactive scoring is explicitly deferred, not designed here.
- **New Xcode target added manually, not scripted.** This needs a Widget Extension target that doesn't exist in the project yet. Hand-scripting a new `PBXNativeTarget` into `project.pbxproj` via text edits carries real risk of corrupting the project file — Xcode's own target-creation wizard correctly wires up Info.plist generation, entitlements, the embed-extension build phase, and product dependencies, which would be error-prone to replicate by hand. **This spec assumes the user has already added a Widget Extension target via Xcode (File > New > Target > Widget Extension, with "Include Live Activity" checked if offered) before implementation begins** — everything below describes what goes inside that scaffold and what changes in the main app, not how to create the target itself.

Because of the read-only scoping decision, this also turns out to need **no App Group, no shared SwiftData container, and no `LiveActivityIntent`** — the main app already has the live `PickleballMatch`/`ActiveMatchController` in its own process; it just needs to push updates to the Activity the same way it already pushes crash-recovery snapshots.

## What it shows

**Lock Screen** (and, automatically, StandBy — see below): both team names, their current scores, which team is serving, and (for Best of 3/5) games won — surfacing games won prominently matters specifically *because* the point score resets to 0-0 the instant a game inside a Best of 3/5 match finishes (the same behavior `ScoringView`'s own "Game Over" alert already exists to announce for the live screen); without the games-won tally sitting right next to it, a sudden "0-0" on the Lock Screen would read as a bug instead of "Game 2 just started." A match-format pill ("Doubles • Best of 3"), matching the style already established on `MatchDetailView`'s summary card. For doubles side-out matches specifically, also shows which server (1 or 2) is up — `ScoringView`'s own serving badge already distinguishes this live; without it here, a doubles team looking at a MagSafe-mounted phone can tell *who's* serving but not which of the two serve attempts they're on.

**Dynamic Island, expanded**: leading region shows Team A's name and score, trailing region shows Team B's, a center or bottom region shows the serving indicator (plus server number for doubles side-out) and games-won tally.

**Dynamic Island, compact**: `compactLeading` and `compactTrailing` show each team's score only (names don't fit at this size) — the serving team's score gets a subtle accent, reusing the same visual language `ScoringView`'s own "SERVING" badge already uses. Both use `.monospacedDigit()` so a single-digit score next to a double-digit one doesn't visually lopside the pill, and each score is paired with a one-letter team-initial mark (not just a bare number) so which side of the camera cutout belongs to which team is legible without unlocking the phone to check.

**Dynamic Island, minimal**: a single small element — just a serving-indicator glyph, since there's no room for two scores and a server indicator at this size.

**StandBy mode**: verified via research, not assumed, and corrected once already after an external review caught a real API misconception in an earlier draft — `ActivityFamily` has exactly two cases, `.medium` (the default, used for both the Lock Screen and StandBy — there is no separate StandBy family) and `.small` (an opt-in for the Apple Watch Smart Stack and CarPlay, not relevant here). `.supplementalActivityFamilies([.medium])` would be a no-op, since `.medium` is already what renders by default; there's no "opt into a dedicated StandBy layout" step to take. In StandBy, the system simply scales the same Lock Screen (`.medium`) presentation up to fill the screen — the way to make that scaled-up result look sharp rather than like an oversized phone widget is to design the one Lock Screen view itself with clean, flexible `Spacer()`-based layout and high-contrast typography that holds up at both 1x and 2x, not to build a second view for a family that doesn't exist. Also worth designing for from the start: a MagSafe-mounted phone in low light or with Always-On Display active switches the Live Activity into reduced-luminance mode (`@Environment(\.isLuminanceReduced)`). Rather than hardcoding an opaque dark background inside the view body, `.activityBackgroundTint(.black.opacity(0.85))` and `.activitySystemActionForegroundColor(.white)` on the `ActivityConfiguration` root let the system dim and tint the scoreboard correctly in that state.

## Where the shared types live

**Not in `PickleballKit`.** That package declares `.iOS(.v17), .watchOS(.v10), .macOS(.v14)` as supported platforms (`PickleballKit/Package.swift`) — it's genuinely built and tested cross-platform (confirmed by its own existing macOS index-build artifacts). `ActivityKit` doesn't exist on macOS at all; importing it anywhere in that package would break the macOS platform target. This follows the same principle already established twice elsewhere in this codebase — keeping the live engine free of wall-clock time, keeping player identity out of it — extended here to keeping platform-specific frameworks out of a package that's deliberately kept portable.

Instead, a new small file (e.g. `ServerTwo/LiveActivity/PickleballActivityAttributes.swift`) is added to **both** the `ServerTwo` app target's membership and the new widget extension target's — the standard pattern for a type two targets both need, when a shared package isn't the right home for it. **This file stays dependency-free — `import ActivityKit` and nothing else, no `import PickleballKit`.** The widget extension only ever *reads* a `ContentState` the system hands it; it never constructs one from a live `PickleballMatch`. Putting the `PickleballMatch`-constructing initializer in this same file, as an earlier draft of this spec did, would force the widget extension to link `PickleballKit` (and transitively SwiftData) just to compile, for a dependency it never actually needs:

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
        // 1 or 2 for a doubles side-out match (mirrors GameState's own
        // `serverNumber`), nil for singles or rally scoring, where the
        // concept of a numbered second server doesn't apply.
        var serverNumber: Int?
        var isMatchOver: Bool
    }

    let teamAName: String
    let teamBName: String
    let matchFormatSummary: String  // e.g. "Doubles • Best of 3" - precomputed, not recomputed per update
}
```

The mapping from live match state to a `ContentState` — a pure function, easily unit-testable — lives in `ActiveMatchController.swift` instead (app target only, where `PickleballMatch` is already a dependency regardless):

```swift
// ServerTwo/ActiveMatchController.swift — NOT in the shared
// PickleballActivityAttributes.swift file (see above).
extension PickleballActivityAttributes.ContentState {
    init(match: PickleballMatch) {
        let state = match.currentGame.state
        self.teamAScore = state.teamAScore
        self.teamBScore = state.teamBScore
        self.teamAGamesWon = match.gamesWon(for: .teamA)
        self.teamBGamesWon = match.gamesWon(for: .teamB)
        self.servingTeamRawValue = state.servingTeam.rawValue
        if match.configuration.playMode == .doubles, case .sideOut = match.configuration.scoringFormat {
            self.serverNumber = state.serverNumber.rawValue
        } else {
            self.serverNumber = nil
        }
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

**`currentActivity` is marked `@ObservationIgnored`.** `ActiveMatchController` is `@Observable`; without this, the macro synthesizes observation tracking for a property nothing in this app's own UI ever reads or displays, triggering pointless SwiftUI view re-evaluations every time an Activity handle is assigned or cleared:

```swift
@ObservationIgnored private var currentActivity: Activity<PickleballActivityAttributes>?
@ObservationIgnored private var pendingUpdateTask: Task<Void, Never>?
```

**Enforcing a single-activity invariant, to avoid zombie and duplicate activities.** Three related failure modes, all real and worth designing against up front rather than discovering later:

1. `endLiveActivity`'s `.end()` call is async; if the user force-quits the app in the moment between `finishMatch()` returning and that `Task` completing, the system has no record that the match ended and can leave the Live Activity stranded on the Lock Screen for hours.
2. If `resumeIfNeeded` finds *no* in-progress match to resume (a normal app launch, not a crash-recovery one), it never runs the resume logic at all today — so a stray activity left over from failure mode 1 would never get cleaned up on the next launch either.
3. If a stray activity from failure mode 1 is still running when a brand new match starts, `Activity.request` in `startLiveActivity` would add a *second*, simultaneous Live Activity rather than replacing the first.

The fix for all three is the same: never assume at most one activity exists; actively enforce it.

**Start**, inside `confirmFirstServe` (right where `persistSnapshot()` is already called after creating the live match) — ending any pre-existing activity of this type before requesting a new one:

```swift
private func startLiveActivity(info: ActiveMatchInfo) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    Task {
        for stale in Activity<PickleballActivityAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
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
}
```

`ActivityAuthorizationInfo().areActivitiesEnabled` is checked and silently no-op'd on `false` (the user disabled Live Activities in Settings) — this is a nice-to-have enhancement layered on top of an app that works completely fine without it, the same resilience posture most of this codebase's `try?`-guarded side effects already take, not a feature the match-scoring flow can ever block on.

**Update**, inside `recordPoint`, `undo`, and `correctScore` — alongside their existing `persistSnapshot()` call. The `ContentState` snapshot is captured synchronously, on the caller's own actor, before any `Task` is entered — both because `ActiveMatchController` runs under this project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting (confirmed in `project.pbxproj`, not assumed) and a capture inside the `Task` closure would otherwise cross that isolation boundary, and because rapid taps (score, then immediately undo) would otherwise spawn multiple unstructured `Task`s with no ordering guarantee between them — a later tap's update could, in principle, be overtaken by an earlier tap's update that happens to finish second, leaving the Activity showing a stale score. Tracking the in-flight task and cancelling any previous one before starting the next makes "last write wins" actually mean the *last call*, not whichever `Task` the scheduler happened to run last:

```swift
private func updateLiveActivity(info: ActiveMatchInfo) {
    guard let currentActivity else { return }
    let content = ActivityContent(
        state: PickleballActivityAttributes.ContentState(match: info.match),
        staleDate: nil
    )
    pendingUpdateTask?.cancel()
    pendingUpdateTask = Task {
        await currentActivity.update(content)
    }
}
```

**End**, inside `finishMatch()` and `cancelActiveMatch()` — cancelling any in-flight update first, so a late `.update()` can never race against and undo an `.end()`:

```swift
private func endLiveActivity() {
    guard let currentActivity else { return }
    pendingUpdateTask?.cancel()
    pendingUpdateTask = nil
    Task {
        await currentActivity.end(nil, dismissalPolicy: .immediate)
    }
    self.currentActivity = nil
}
```

**Resume** (`resumeIfNeeded`, after a crash/relaunch): Live Activities are managed by the system, independent of the app's own process — a crash doesn't necessarily kill a running Activity. Called right after `resumeIfNeeded` constructs its `ActiveMatchInfo` (the same `info` `startLiveActivity`/`updateLiveActivity` already take, so this slots into the existing method without a new parameter shape):

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

**Also**, at the point `resumeIfNeeded` finds *no* in-progress match to resume — the failure mode 2 case above, a stray activity with no corresponding live match at all:

```swift
// In resumeIfNeeded(), the branch where loadInProgressMatch returns nil:
Task {
    for stray in Activity<PickleballActivityAttributes>.activities {
        await stray.end(nil, dismissalPolicy: .immediate)
    }
}
```

`currentActivity`/`pendingUpdateTask` are new, non-persisted properties on `ActiveMatchController` — they don't need to survive a relaunch themselves (the code above re-discovers or cleans up on resume), so they're the same category of live-only state as the Doubles L/R spec's swap-toggle booleans, not something written to `GameRecord`/`MatchRecord`.

## Entitlement

`INFOPLIST_KEY_NSSupportsLiveActivities = YES` added to the `ServerTwo` app target's Debug and Release build settings — the exact same mechanism, and the exact same two call sites (`project.pbxproj`'s app-target Debug/Release configurations), as the `INFOPLIST_KEY_UIBackgroundModes` fix already applied for CloudKit earlier in this session.

## Scaffold cleanup and deep-linking

Two things to handle while working inside the Xcode-generated widget extension target (see Context above), neither of which is part of the ActivityKit logic itself but both of which are easy to miss:

**Delete the template's placeholder Home Screen widget.** Xcode's Widget Extension wizard, with "Include Live Activity" checked, generates *two* widgets bundled together in one `WidgetBundle`: the Live Activity this spec designs, and an unrelated dummy Home Screen timeline widget (an emoji/clock placeholder, typically `<TargetName>.swift`) that nothing in this feature asked for. Left in place, it ships a broken-looking placeholder widget in the Home Screen widget gallery. It should be deleted (and removed from the `WidgetBundle`), leaving only the Live Activity widget.

**Tapping the Live Activity should open the live match, not wherever the app happened to be.** By default, tapping a Live Activity on the Lock Screen or in the Dynamic Island just foregrounds the app wherever it was last left — if the user had switched to History or Settings before locking their phone, tapping the scoreboard drops them there instead of on the match. Adding `.widgetURL(URL(string: "servertwo://play"))` to the Live Activity's view, and handling `.onOpenURL` at `RootTabView` to select `.play`, makes tapping the Live Activity always surface the live scoreboard.

## Testing

**What's actually testable, and what isn't — stated plainly rather than overclaimed.** There's no XCTest API for asserting what's rendered inside a Live Activity or Dynamic Island; UI tests cannot inspect that content. What *is* testable without any ActivityKit involvement:

- Unit tests on `PickleballActivityAttributes.ContentState.init(match:)` — a pure mapping function — covering: scores reflect `currentGame.state`; games-won reflects `match.gamesWon(for:)` for Best of 3/5; `isMatchOver` flips correctly; `servingTeamRawValue` matches `state.servingTeam.rawValue`; `serverNumber` is populated for doubles side-out and `nil` for singles and for rally scoring (either freeze setting).
- A test confirming `ActiveMatchController` gracefully no-ops its Live Activity calls (doesn't throw, doesn't crash) when `ActivityAuthorizationInfo().areActivitiesEnabled` is `false` — simulating the user having disabled Live Activities.
- A test confirming rapid sequential calls to `updateLiveActivity` (simulating fast repeated taps) leave exactly one pending update task, not several racing ones — covers the out-of-order-update fix.
- A test confirming `startLiveActivity` ends any pre-existing activities of this type before requesting a new one (the duplicate-activity fix), and that the "no match to resume" branch of `resumeIfNeeded` ends any stray activities even when there's no live match to attach them to (the zombie-activity fix).
- Manual, on-device or simulator verification (screenshot-based, the same empirical standard this session has held for every other visual feature) of the actual Lock Screen, all three Dynamic Island presentations, and StandBy appearance — this cannot be automated, and the spec doesn't pretend otherwise.

## Non-goals

- No interactive Lock Screen scoring buttons — see Context above. A future spec, if pursued, would need its own research into the current (not two-OS-versions-stale) `LiveActivityIntent` process-location behavior before any design commitment.
- No push-notification-driven remote updates (`pushType` is passed as implicit `nil`/local-only in `Activity.request`) — this app has no backend, consistent with its established zero-custom-backend architecture; all updates originate from the app's own live scoring session, never a server.
- No Apple Watch or CarPlay presentation (`supplementalActivityFamilies([.small])`, the one opt-in `ActivityFamily` actually offers) — not requested, and not designed here. Note this is unrelated to StandBy, which uses the same default `.medium` family as the Lock Screen (see "What it shows" above) and needs no opt-in of its own.

## As built

Where this section and the text above differ, this section is what the code does.

**The extension target.** `ServerTwoLiveActivity` (`com.delonsampaio.ServerTwo.LiveActivity`) was added by a minimal text edit of `project.pbxproj` (170 added lines, none changed or removed), not through the Xcode wizard. A round trip of the project through the `xcodeproj` gem was tried first and only changed cosmetics (comment labels on build configurations and empty `exceptions`/`dependencies` arrays), so the gem was used only to prove the file model was understood and the real file was edited by hand to keep the diff to the new target. `xcodebuild -list` and a build of the `ServerTwo` scheme (which builds the extension as a dependency and embeds it under `PlugIns/`) verify it. It is iOS-only (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`, `platformFilter = ios` on the embed and the dependency, because the app also lists macOS/visionOS platforms where ActivityKit does not exist), Swift 6, MainActor default isolation like the app, same development team. The `Info.plist` holds `NSExtension` (`com.apple.widgetkit-extension`) and is excluded from the synchronized group. The placeholder Home Screen widget from the template was never added: the bundle contains only the Live Activity. `INFOPLIST_KEY_NSSupportsLiveActivities = YES` is on the app target (Debug and Release). Frameworks are autolinked from the `import`s.

**Sharing the attributes.** `PickleballActivityAttributes` lives in a top-level folder `ServerTwoLiveActivityShared/`, a synchronized group that is a member of BOTH targets. This was chosen over a local package because it needs no `public` API surface, no package plumbing, and the two targets compile the identical source; ActivityKit stays out of `PickleballKit`. The types are explicitly `nonisolated` (both targets default to MainActor, and an isolated `ActivityAttributes` conformance does not compile). One static field was added to the spec's three: `showsGamesWon` (false for Best of 1), so the extension does not parse `matchFormatSummary` to decide whether to show the tally.

**Mapping and summary.** `ContentState.init(match:)` and `PickleballActivityAttributes.init(match:teamAName:teamBName:)` are in the app target (`ServerTwo/LiveActivity/PickleballActivityAttributes+Match.swift`). `GameConfiguration.summaryText(matchFormat:)` was extracted into PickleballKit as specified; `MatchDetailView` now calls it (same text: "Doubles • Best of 3", "Singles • Best of 1 • Rally").

**Controller.** `LiveActivityController` (app target) sits behind a `LiveActivityHosting` protocol (`ActivityKitLiveActivityHost` for real, `NoOpLiveActivityHost` for any `-UITest-` launch argument and as the default for unit tests; `MyApp.makeLiveActivityHost` mirrors `makeSpeechOutput`). Differences from the sketch above:
- Every ActivityKit call runs on one serial chain instead of cancelling a pending task, so ordering is guaranteed and an update cannot race an end.
- It is driven from the same points as `persistSnapshot()` (`confirmFirstServe` begins, `recordPoint`/`undo`/`correctScores` update, `finishMatch`/`cancelActiveMatch` end, `resumeIfNeeded` resumes or ends strays). Updates are skipped when the state is identical (timeouts change nothing shown).
- A finished match ends with its final state and `.after(now + 5 min)`; a cancelled match ends immediately. (`finishMatch` throws for a match that is not over, so there is no "finish early" case.)
- Resume only attaches to a running activity whose static attributes (names, format) equal the match being resumed; anything else is ended and a new one started, because static attributes cannot be changed on a running activity.
- `staleDate` is 3 hours after each push (a break between games must not look like a fault); the Lock Screen view then says "Out of date".
- If the first `Activity.request` failed, or Live Activities were off at the start, there is exactly one retry per match: from the next `update` that carries a changed state, or when the app becomes active (`retryIfNeeded`). It never re-requests after `end`, and never after the user swipes the activity away (the handle then still exists).
- `Activity` is not `Sendable`, so the real handle stores only the activity id and attributes and looks the instance up for each call (no `@unchecked Sendable`).
- Updates come from the app process, so they keep working while the app is in the background as long as the process runs; nothing extra was needed.

**Views.** `ServerTwoLiveActivity/PickleballLiveActivity.swift`: Lock Screen/StandBy (`.medium`, the one presentation scaled by the system), Dynamic Island expanded/compact/minimal. The Lock Screen view is two rows to stay under Apple's 160 pt cap: a summary line with the games tally inline ("Doubles • Best of 3 · Games 1–0", plus "Match Complete"/"Out of date"), then both teams in two equal-width columns split by a 1 pt divider (`Color.primary.opacity(0.15)`): a one-line name that shrinks instead of wrapping, a 54 pt rounded score centred under it, and a reserved caption line under the score ("SERVER n" / "SERVING", accent colour, invisible on the receiving side but laid out in both columns so the scores stay level). The first on-device sighting (a real iPhone) showed the card renders (about 102 pt tall) but the scores were off-centre: the serving label sat beside the score in an HStack and, hidden or not, took layout width, pushing each score left by half of it. It now has its own line (a trailing overlay has no room beside a two-digit score in a half-width column). The Dynamic Type size is capped at xxxLarge for the whole view. Height, from an `ImageRenderer` pass of the layout at 380 pt wide (not a device): padding 10 + 10, summary 16, spacing 4, name 20, score line box 48 (trimmed to 0.88x the font size), serving line 13 = about 118 pt at the default size and about 147 pt at the xxxLarge cap (long names shrink and render a little shorter), under the 160 pt cap. The minimal Dynamic Island shows a static pickleball glyph (a checkmark once the match is over): it does NOT show who is serving. The compact presentation shows each score with a team initial, the serving team's score accented and bold. `.widgetURL(servertwo://play)` with `.onOpenURL` in `RootTabView` selecting Play. Colours are copies of the app's `AccentColor`, `AccentText` and `SecondaryText` colour sets in the extension's own asset catalog; the Lock Screen view forces the dark scheme because its surface is always dark (`activityBackgroundTint(.black.opacity(0.85))`). Previews exist for each presentation.

**ActivityKit guards.** The app target also lists visionOS, which has no ActivityKit. `PickleballActivityAttributes` is a plain value type; only its `ActivityAttributes` conformance and `ActivityKitLiveActivityHost` are inside `#if canImport(ActivityKit)`, and `MyApp.makeLiveActivityHost` falls back to the no-op host there.

**Settings switch.** Settings > Audio & Haptics has a "Live Activity" switch (`AppSettings.liveActivityEnabled`, on by default, UI id `Settings.LiveActivityToggle`). `LiveActivityController` takes an `isEnabled` closure (set up in `MyApp` like the announcer's); while off, `begin`/`resume`/`update`/retry start nothing and send nothing (the current state is still remembered). Flipping it calls `enablementChanged()` from `.onChange`: off ends the running activity with the `.immediate` policy, on starts (or attaches to) one for the match in progress with its current state, never a duplicate. Both go through the serial chain, so quick toggles settle on the last one. Scoring is unaffected, and it is separate from the system's own switch (`areActivitiesEnabled`), which still applies.

**Debug seam.** `-Debug-DemoLiveActivity` (Debug builds only) starts a sample activity at launch.

### Not verified / device checklist

The spec's own testing standard (screenshot verification of the Lock Screen, all three Dynamic Island presentations and StandBy) was NOT met. Nothing about the Live Activity was ever seen: the simulator in this environment is headless, a run with `-Debug-DemoLiveActivity` showed no activity and no controller log line, and the Xcode previews were never rendered. Unit tests cover the mapping and the controller logic against a fake host only. Unverified:

- how any of the presentations look (Lock Screen, StandBy in charging/landscape/night mode, Dynamic Island expanded/compact/minimal, Always-On dimming), including the Lock Screen height estimate against the 160 pt cap;
- Dynamic Type up to and past the xxxLarge cap, and VoiceOver reading of the score elements ("<name>, N points", serving, games won);
- that updates keep arriving while the app is in the background;
- that tapping the activity opens the Play tab: `servertwo://play` is routed with `.widgetURL` and `.onOpenURL` and no `CFBundleURLTypes` is registered, which is expected to work for a widget URL but was not tried;
- `Activity.request` timing at a cold launch and on resume after a force quit (the activity should re-attach, not duplicate);
- Settings > Server Two > Live Activities off (scoring must be unaffected), and the single retry after a failed start;
- the "Out of date" hint after 3 hours without an update;
- Archive, signing and App Store validation of the new bundle id `com.delonsampaio.ServerTwo.LiveActivity` (and a visionOS build, if that platform is still wanted).
