# Accessibility Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every screen usable at the largest Dynamic Type sizes, with VoiceOver, with Reduce Motion on, and without colour as the only signal, with no change to scoring or to the default-size look.

**Architecture:** Pure helpers (spoken strings, sheet detent policy, coin-flip animation plan) carry the logic so they can be unit-tested; views call them. An XCUITest accessibility audit lands first in report-only mode and is switched to strict in the last task. `VoiceAnnouncer` gains a VoiceOver path that posts accessibility announcements instead of speaking.

**Tech Stack:** SwiftUI (iOS 27, Liquid Glass), Swift 6 language mode (app target has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), XCTest / XCUITest `performAccessibilityAudit`, `AccessibilityNotification.Announcement`, `@AccessibilityFocusState`, `@ScaledMetric`.

**Spec:** `docs/superpowers/specs/2026-10-17-accessibility-pass-design.md` (approved 2026-10-18; read its "What the code does today" and "Review changes" sections first)

## Global Constraints

- Swift 6 language mode: new code compiles without warnings or escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`); callbacks are explicitly `@MainActor`.
- Default text size must look unchanged (same layout apart from rounding). Only accessibility sizes change layout.
- No change to scoring, rules, planner wording, persistence or navigation. No new colours, no new settings.
- Existing accessibility identifiers are never renamed or removed. Existing UI tests query `app.staticTexts[...]` by identifier for: history rows ("<A> vs <B>"), manage-players rows ("PlayerRow.<name>", "Me.<name>"), the home record card ("Your Record", "YourRecordValue", "RecentForm"). Do NOT put `.accessibilityElement(children: .combine)` on those rows or cards; if a task cannot avoid touching a tested element, it updates that test in the same commit and keeps its intent.
- The score zone label keeps starting "<name>, <N> points" (tests use `contains("12 points")` and parse the digits after the first ", ").
- Touch targets at least 44x44 pt.
- Only these rule numbers may be cited in code or docs: none are needed in this plan.
- Run app tests ONLY on simulator `3C7D4B7A-F035-4AD7-89FF-B08256AF2516` (if shut down, `xcrun simctl boot` it), serially: `xcodebuild test -scheme ServerTwo -destination 'platform=iOS Simulator,id=3C7D4B7A-F035-4AD7-89FF-B08256AF2516' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:<Target/Class> -resultBundlePath /tmp/<name>.xcresult`, and verify with `xcrun xcresulttool get test-results summary --path /tmp/<name>.xcresult`. Never `name=iPhone 17 Pro`. Run focused classes per task; the full suite only in Task 5. Prove a fresh compile (`SwiftCompile` lines for touched files) before trusting a warning grep; delete stale `ServerTwo*.build` intermediates if needed. SourceKit "No such module" errors are false.
- Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Never stage `ServerTwo.xcodeproj/xcuserdata/**/xcschememanagement.plist`. Do not push.

## Review Focus

1. VoiceOver on and the Voice Announcer toggle OFF: announcements are still posted (the toggle must not silence VoiceOver users). Pinned in Task 3.
2. VoiceOver off and toggle OFF: nothing is spoken and nothing is posted. Pinned in Task 3.
3. Score zone: the serving team's label says ", serving", the other does not, and the label still starts "<name>, <N> points". Pinned in Task 4.
4. Reduce Motion coin flip: the result settles immediately, no spin, no timed letter changes, and "Begin Match" gets VoiceOver focus. Pinned in Task 5 (pure plan test) and the manual list.
5. Accessibility-size sheets: the Game Over and Finish Match buttons are reachable (second detent plus scrolling) and a two-digit score digit does not wrap. Pinned by the strict audit at accessibility size 4 in Task 5.

---

## File Structure

- Create `ServerTwo/Accessibility/AccessibilityText.swift`: pure spoken-string helpers.
- Create `ServerTwo/Accessibility/AdaptiveSheet.swift`: detent policy plus the `adaptiveSheet(height:)` view modifier.
- Create `ServerTwo/Setup/CoinFlipAnimationPlan.swift`: pure plan for the coin flip animation.
- Modify `ServerTwo/Voice/VoiceAnnouncer.swift`, `ServerTwo/Scoring/ScoringView.swift`, `ScoringPromptSheet.swift`, `FinishMatchSheet.swift`, `ScoreCorrectionSheet.swift`, `ServerTwo/Setup/CoinFlipView.swift`, `ServerTwo/Players/ManagePlayersView.swift`, `PlayerDetailView.swift`, `ServerTwo/Home/HomeView.swift`, `ServerTwo/History/MatchHistoryListView.swift`, `MatchDetailView.swift`, and other views the audit names.
- Create tests: `ServerTwoTests/AccessibilityTextTests.swift`, `AdaptiveSheetTests.swift`, `CoinFlipAnimationPlanTests.swift`, `ServerTwoUITests/AccessibilityAuditUITests.swift`. Modify `ServerTwoTests/VoiceAnnouncerTests.swift`.

---

### Task 1: Accessibility audit harness (report-only)

**Files:**
- Create: `ServerTwoUITests/AccessibilityAuditUITests.swift`

**Interfaces:**
- Produces: a UI test class `AccessibilityAuditUITests` with `private let strict = false` (Task 5 flips it) and a helper `audit(_ app: XCUIApplication, screen: String)` that runs `app.performAccessibilityAudit()` with an issue handler that records each issue into a per-run list (`screen`, `issue.auditType`, `issue.compactDescription`, `issue.element?.identifier`), prints it, always returns `true` (ignored) while `strict == false`; in strict mode it returns `true` only for issues matching an explicit `knownFalsePositives` list (each entry has a comment saying why) and `false` otherwise.

- [ ] **Step 1: Write the harness and one test per screen.** Tests, each launching with `-UITest-ResetState` and calling `dismissOnboardingIfPresented`: `testHome`, `testMatchSetup` (Play tab), `testCoinFlip` (Start Match, scrolling with `scrollUntilVisible`), `testScoring` (Begin Match; also open the Cancel Match prompt via the "Cancel Match" button, audit it, tap "Keep Playing"), `testHistoryAndMatchDetail` (play and finish a one-game match as `GoldenPathUITests` does, then History tab, audit the list, open the row, audit the detail), `testPlayersAndSettings` (Settings tab, audit, open "Manage Players", audit), `testHowToPlay` (Settings, its link), `testOnboarding` (launch with `-UITest-ResetState` and audit BEFORE dismissing), `testPaywall` (reachable via the Home unlock banner "Home Unlock Pro Banner" or the paywall trigger used by `PaywallTriggerUITests`; reuse its launch arguments). Add `testScoringAtAccessibilitySize`: same as `testScoring` plus `app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL"]` and a sanity assertion that the larger size really applied (for example the "First Serve" or "Decide who serves first" text frame height is greater than the same element's height in a default-size launch, captured in the same test by launching twice).
- [ ] **Step 2: Run** the class once (`-only-testing:ServerTwoUITests/AccessibilityAuditUITests`). Expected: all tests pass (report-only).
- [ ] **Step 3: Save the findings.** Write every printed issue, grouped by screen, to `docs/superpowers/plans/2026-10-18-accessibility-audit-findings.md` (a table: screen, audit type, element, description). This file is the work list for Tasks 2-5 and is committed.
- [ ] **Step 4: Commit** `ServerTwoUITests/AccessibilityAuditUITests.swift` and the findings file.

---

### Task 2: Dynamic Type and sheet detents

**Files:**
- Create: `ServerTwo/Accessibility/AdaptiveSheet.swift`, `ServerTwoTests/AdaptiveSheetTests.swift`
- Modify: `ScoringView.swift` (digits 108 pt, fixed 28 pt badge slot), `ScoreCorrectionSheet.swift` (64 pt digits, `.height(360)` + `.large`, `minimumScaleFactor`), `ScoringPromptSheet.swift` (`detentHeight`, 64 pt and 28 pt fonts, `minimumScaleFactor`), `FinishMatchSheet.swift` (`.height(320)`, 36 pt and 28 pt fonts), `ManagePlayersView.swift` (two `.height(180)` sheets, `.controlSize(.small)` buttons), `MatchDetailView.swift`, `MatchHistoryListView.swift`, `HomeView.swift`, `PlayerDetailView.swift`, `CoinFlipView.swift`, `PaywallView.swift`, `OnboardingView.swift`, `MatchRecapCardView.swift` (leave the share card at its fixed 360 square: it is an exported image), plus every Dynamic Type or hit-region item in the Task 1 findings.

**Interfaces:**
- Produces:
  - `enum SheetDetentPolicy { static func detents(height: CGFloat, isAccessibilitySize: Bool) -> [PresentationDetent] }`: returns `[.height(height)]`, plus `.large` when `isAccessibilitySize`.
  - `extension View { func adaptiveSheet(height: CGFloat) -> some View }`: scales `height` with `@ScaledMetric(relativeTo: .body)`, wraps nothing itself; applies `.presentationDetents(SheetDetentPolicy.detents(...))` using `@Environment(\.dynamicTypeSize).isAccessibilitySize`. The content is wrapped in a `ScrollView { }.scrollBounceBehavior(.basedOnSize)` by the helper so it is inert while the content fits.

- [ ] **Step 1: Write `AdaptiveSheetTests`:** `testNormalSizeHasOneDetent` (`detents(height: 320, isAccessibilitySize: false) == [.height(320)]`), `testAccessibilitySizeAddsLarge` (`== [.height(320), .large]`).
- [ ] **Step 2: Run** `ServerTwoTests/AdaptiveSheetTests`; expected: FAIL (types missing).
- [ ] **Step 3: Implement** `SheetDetentPolicy` and `adaptiveSheet(height:)` in `ServerTwo/Accessibility/AdaptiveSheet.swift`. No `GeometryReader`/preference measuring of content (it causes layout loops).
- [ ] **Step 4: Run** the class; expected: PASS.
- [ ] **Step 5: Apply `adaptiveSheet` to the five fixed-height sheets.** `ScoringPromptSheet` passes its existing `detentHeight` value as `height`. `FinishMatchSheet` and `ScoringPromptSheet` draw their own card with `.presentationBackground(.clear)`: keep that card and its look; the scroll view goes inside the card, and the card must still fill the detent at default size. Keep `ScoringPromptSheet`'s drag indicator as is; do not add a drag indicator to `FinishMatchSheet` at default size.
- [ ] **Step 6: Fixed fonts.** Replace each fixed `.font(.system(size:...))` in the file list with a scaled size (`@ScaledMetric(relativeTo: .largeTitle)` or the closest text style) keeping the default size equal to today's value. Cap the 108 pt score digits in `ScoringView` (`.dynamicTypeSize(...DynamicTypeSize.accessibility2)` on that text, or `min(scaled, 128)`) so a two-digit score never wraps; keep the team name and the "SERVING" badge scaling. Remove `minimumScaleFactor` where the text can wrap or the container can grow; keep it only on the share card.
- [ ] **Step 7: Icons, columns, hit targets.** Make decorative icon frames (22, 28, 53, 60) and fixed text-column widths (54, 56, 68) scale with `@ScaledMetric`, or switch the row to stacked layout at `dynamicTypeSize.isAccessibilitySize` (`ViewThatFits`). Give `.controlSize(.small)` buttons in `HomeView` and `ManagePlayersView` a 44 pt minimum height (`.frame(minHeight: 44)` plus `.contentShape(Rectangle())`), keeping the default-size look as close as possible. Fix the contrast and hit-region findings from Task 1 that belong to this task's files.
- [ ] **Step 8: Verify** at default size by eye in the simulator (home, scoring, each sheet: unchanged) and at accessibility size 4 (`xcrun simctl ui <sim> content_size accessibility-extra-extra-large`; restore with `... large` afterwards). Run `ServerTwoTests` (the whole unit target) and `ServerTwoUITests/ScoringPromptsUITests`, `ScoreCorrectionUITests`, `SavedPlayersUITests`; expected: all pass; fresh-compile warning grep empty.
- [ ] **Step 9: Commit.**

---

### Task 3: VoiceOver announcement path

**Files:**
- Modify: `ServerTwo/Voice/VoiceAnnouncer.swift`, `ServerTwoTests/VoiceAnnouncerTests.swift`, and its construction sites (`MyApp.swift`; keep the default arguments so other call sites compile unchanged).

**Interfaces:**
- Produces: `VoiceAnnouncer.init(output:isEnabled:isVoiceOverRunning:postAnnouncement:)` with a new last parameter `postAnnouncement: @escaping @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }`. `announce(_ lines: [String])`: if `lines` is empty, do nothing; else if `isVoiceOverRunning()`, call `postAnnouncement(lines.joined(separator: " "))` regardless of `isEnabled()` and do not speak; else existing behaviour (speak only when enabled). `stop()` unchanged.

- [ ] **Step 1: Update/add tests in `VoiceAnnouncerTests`** (the existing VoiceOver test asserted silence; its intent changes to "never spoken by the synthesizer"): `testWithVoiceOverRunningTheLinesAreAnnouncedNotSpoken` (output has no speak; `postAnnouncement` received "Side out. Fred serving. 2, 4, 1."), `testWithVoiceOverRunningAndTheToggleOffTheLinesAreStillAnnounced` (review focus 1), `testWithVoiceOverOffAndTheToggleOffNothingIsSpokenOrPosted` (review focus 2), `testEmptyLinesPostNothingUnderVoiceOver`. Keep the other tests.
- [ ] **Step 2: Run** `ServerTwoTests/VoiceAnnouncerTests`; expected: FAIL (compile error or assertion).
- [ ] **Step 3: Implement** the new parameter and branch in `VoiceAnnouncer.swift`; update the doc comment (it currently says the announcer stays silent under VoiceOver). Update `MyApp.swift` only if its construction needs the new argument (the default should make that unnecessary).
- [ ] **Step 4: Run** `VoiceAnnouncerTests` and `MyAppSpeechOutputTests`; expected: PASS; fresh-compile warning grep empty.
- [ ] **Step 5: Commit.**

---

### Task 4: VoiceOver labels, values and focus

**Files:**
- Create: `ServerTwo/Accessibility/AccessibilityText.swift`, `ServerTwoTests/AccessibilityTextTests.swift`
- Modify: `ScoringView.swift` (score zone, Finish Match focus), `CoinFlipView.swift` (announcement and focus), `HomeView.swift`, `MatchHistoryListView.swift`, `PlayerDetailView.swift`, `MatchDetailView.swift`, `ManagePlayersView.swift`, and the labels the Task 1 findings name.

**Interfaces:**
- Produces (all `static` on `enum AccessibilityText`, pure):
  - `scoreZoneLabel(name: String, score: Int, isServing: Bool) -> String`: `"<name>, <score> points"`, plus `", serving"` when `isServing`.
  - `scoreZoneHint: String` = `"Double tap to score a point. Use the Actions rotor to correct the score."`
  - `resultWord(didWin: Bool) -> String`: `"Won"` / `"Lost"`.
  - `recentFormValue(_ form: [Bool]) -> String`: results oldest-to-newest joined by `", "`, e.g. `"Won, Lost, Won"` (the caller passes the same order as it displays).
  - `pointRowLabel(sequence: Int, scorerName: String, scoreAfter: String) -> String`: `"Point <n>, <scorerName> scored, <scoreAfter>"` where `scoreAfter` is like `"4-2"`.

- [ ] **Step 1: Write `AccessibilityTextTests`:** `testScoreZoneLabelStartsWithNameAndPoints` (`"Delon, 12 points"` when not serving; `"Delon, 12 points, serving"` when serving; both start with "Delon, 12 points"), `testScoreZoneLabelLeavesTheDigitsParseableAfterTheFirstComma` (the same parsing the UI test uses returns 12), `testResultWords`, `testRecentFormValueKeepsTheGivenOrder`, `testEmptyRecentFormIsAnEmptyString`, `testPointRowLabel`. 
- [ ] **Step 2: Run** `AccessibilityTextTests`; expected: FAIL (type missing).
- [ ] **Step 3: Implement** `AccessibilityText`.
- [ ] **Step 4: Run** the class; expected: PASS.
- [ ] **Step 5: Score zone.** In `ScoringView.scoreZone(for:match:)` use `AccessibilityText.scoreZoneLabel(name:score:isServing:)` for `.accessibilityLabel` (the identifier `scoreZone.<team>`, the button trait, the default action and the "Correct score" action stay) and `.accessibilityHint(AccessibilityText.scoreZoneHint)`.
- [ ] **Step 6: Badges and strips.** The W/L badges in `HomeView`, `MatchHistoryListView` and `PlayerDetailView` get `.accessibilityLabel(AccessibilityText.resultWord(didWin:))` on the badge `Text` itself (the row is not combined; the "<A> vs <B>" identifier element is untouched). The "RecentForm" strip in Home and Player detail becomes one element: `.accessibilityElement(children: .ignore)`, `.accessibilityLabel("Recent form")`, `.accessibilityValue(AccessibilityText.recentFormValue(...))`, keeping the `RecentForm` identifier. `MatchDetailView` point rows: `.accessibilityElement(children: .combine)` with `.accessibilityLabel(AccessibilityText.pointRowLabel(...))`; hide the 6 pt colour dot. Add labels the Task 1 findings require for icon-only controls and header traits on section titles.
- [ ] **Step 7: Coin flip and match end.** In `CoinFlipView.settle(on:)` post `AccessibilityNotification.Announcement("<team name> serves first").post()` and set an `@AccessibilityFocusState` bool that focuses the "Begin Match" button. In `ScoringView`, when `match.isMatchOver` becomes true (observe it with `onChange`), move VoiceOver focus to the "Finish Match" button with an `@AccessibilityFocusState`. (The "Game and match" announcement itself already comes from Task 3's path.)
- [ ] **Step 8: Run** `ServerTwoTests` (whole unit target) and the UI classes that query tested elements: `HistoryFilterUITests`, `QuickLogUITests`, `ChemistryRowsUITests`, `SavedPlayersUITests`, `ScoreCorrectionUITests`, `ScoreZoneGestureUITests`, `ScoringPromptsUITests`, `GoldenPathUITests`; expected: all pass; fresh-compile warning grep empty.
- [ ] **Step 9: Commit.**

---

### Task 5: Reduce Motion, strict audit, final pass

**Files:**
- Create: `ServerTwo/Setup/CoinFlipAnimationPlan.swift`, `ServerTwoTests/CoinFlipAnimationPlanTests.swift`
- Modify: `CoinFlipView.swift`, `ScoreCorrectionSheet.swift` (`.contentTransition(.numericText())`), `ServerTwoUITests/AccessibilityAuditUITests.swift`, plus any file the strict audit points to; update `docs/superpowers/specs/2026-10-17-accessibility-pass-design.md` ("As built") and the roadmap.

**Interfaces:**
- Produces: `struct CoinFlipAnimationPlan: Equatable { let spins: Bool; let letterToggles: Int; let settleDelay: TimeInterval; static func plan(reduceMotion: Bool) -> CoinFlipAnimationPlan }`: `plan(reduceMotion: false)` equals `.init(spins: true, letterToggles: 6, settleDelay: 0.7)` (today's values); `plan(reduceMotion: true)` equals `.init(spins: false, letterToggles: 0, settleDelay: 0)`.

- [ ] **Step 1: Write `CoinFlipAnimationPlanTests`:** `testNormalPlanMatchesTheCurrentAnimation`, `testReduceMotionPlanHasNoSpinNoToggleAndNoDelay`.
- [ ] **Step 2: Run** the class; expected: FAIL.
- [ ] **Step 3: Implement** `CoinFlipAnimationPlan`; use it in `CoinFlipView.flip()` with `@Environment(\.accessibilityReduceMotion)`: when `spins` is false skip `withAnimation` and the `asyncAfter` toggles and call `settle(on:)` immediately. Behaviour with Reduce Motion off must stay identical (same outcome distribution, same timings). Remove `.contentTransition(.numericText())` in `ScoreCorrectionSheet` when `reduceMotion` is true.
- [ ] **Step 4: Run** `CoinFlipAnimationPlanTests`; expected: PASS.
- [ ] **Step 5: Go strict.** In `AccessibilityAuditUITests` set `strict = true`, populate `knownFalsePositives` ONLY for findings that are genuinely system UI or false positives (one entry each, with a comment of why, auditType and element identifier); fix every other reported issue in code. Re-run the audit class (default size and `testScoringAtAccessibilitySize`) until it passes without ignoring real issues. Also extend `testScoringAtAccessibilitySize` to open the Game Over sheet (play game 1 of a best of 3 to its end as `ScoringPromptsUITests` does) and the Finish Match sheet and assert their buttons are hittable at accessibility size 4.
- [ ] **Step 6: Full verification.** Run the full app suite ONCE (all targets) with `-resultBundlePath /tmp/a11y-full.xcresult > /tmp/a11y-full.log 2>&1` and PickleballKit (`cd PickleballKit && swift test`, expected unchanged 174). Expected: app suite all passing (182 plus the new tests), PickleballKit 174, no warnings in project sources (fresh-compile proof).
- [ ] **Step 7: Docs.** Add an "As built" section to the spec (what changed, audit ignores and why, the Task 1 findings that were real); keep the owed device checks list below in it. Do not edit the roadmap (the controller does).
- [ ] **Step 8: Commit.**

---

## Device checks owed (for the user, after the build)

- VoiceOver on: scoring screen reads "<name>, <N> points, serving" for the serving team only; double-tap scores; the new score / side out / game end is spoken once (watch for double reading: VoiceOver re-reading the label PLUS our announcement; if it doubles, report it); flip the coin: announcement and focus lands on Begin Match; match over: focus lands on Finish Match; history row, recent form and point rows read as single sensible stops.
- Voice Announcer toggle OFF with VoiceOver on: scores are still announced; VoiceOver off with the toggle off: silent.
- Text size at the largest accessibility setting: open Home, Play, History, Settings, Manage Players, Add/Rename Player, the scoring screen (two-digit scores), Game Over, Switch Sides, Cancel Match, Score Correction and Finish Match sheets: nothing clipped, every button reachable.
- Reduce Motion on: the coin flip settles instantly with the same result.
