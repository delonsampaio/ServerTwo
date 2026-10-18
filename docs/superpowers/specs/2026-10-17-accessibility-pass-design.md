# Accessibility Pass Design (Phase 7)

**Date:** 2026-10-17
**Status:** Approved by the user on 2026-10-18 ("do what you think is best"), with every default below accepted, including Q4 (VoiceOver users always get the spoken announcements). See "Review changes" at the end.
**Builds on:** Phase 7 "Audio & Accessibility" on the roadmap (the Voice Announcer half is already built)

## Goal

Make every screen of the app usable (1) at the largest Dynamic Type sizes, (2) with VoiceOver, (3) with Reduce Motion on, and (4) without relying on colour alone. No new features, no rules or scoring changes, no visual redesign at the default text size.

Pickleball is played outdoors, one-handed, often at arm's length, so large readable text is a core need and not only an accessibility nicety. The scoreboard digits stay the biggest thing on the screen at every setting.

## What the code does today (verified by reading the source, 2026-10-17)

- **VoiceOver, mostly good on the scoring screen:** each score zone is one element with a button trait, a label ("<name>, <n> points. Tap to score, double tap and hold to correct."), a default action and a named "Correct score" action (`ScoringView.swift` ~429-440). The timeout buttons, Undo, the Score Correction sheet (steppers with labels and values), the prompt sheets (containers, header trait) and onboarding (decorative images hidden) have labels.
- **VoiceOver gap on the scoring screen (found in review, verified):** the zone ignores its children, so the visible "SERVING" badge is never spoken, and `CourtDiagramView` (which had a full spoken description) is not used on the scoring screen any more (only a code comment mentions it). A VoiceOver user cannot tell who is serving. The usage instructions are also inside the label instead of a hint.
- **VoiceOver feedback after a point:** the Voice Announcer is silent while VoiceOver runs (`VoiceAnnouncer.swift:27`, tested) so the two never talk over each other, but nothing replaces it: after a double-tap the label changes and VoiceOver does not necessarily re-read it, so a VoiceOver user may get no confirmation of the new score, a side-out, or the game ending.
- **Dynamic Type gaps:**
  - 15 fixed `.font(.system(size: ...))` uses: the big score digits (108 pt in `ScoringView`, 64 pt in the correction and prompt sheets, 36-48 pt elsewhere), coin flip, paywall, onboarding, avatar initials.
  - Fixed-height sheets: `ManagePlayersView` rename and add sheets `.height(180)` (two places), `FinishMatchSheet` `.height(320)`, `ScoreCorrectionSheet` `.height(360)` plus `.large`, `ScoringPromptSheet` `.height(detentHeight)`.
  - Fixed-size icons and badges (22x22, 28x28, 53x53, 60x60 frames) and fixed-width text columns (54, 56, 68 pt) in History, Home, Player detail and Match setup.
  - `minimumScaleFactor` is used as a shrink-to-fit on score columns (0.6-0.85), which makes text smaller at the sizes where people need it larger.
- **Accessibility labels are sparse outside the scoring flow:** Home, History, Players, Settings, Match setup, Coin flip, Paywall and the recap share button have no explicit labels or hints, so VoiceOver reads whatever SwiftUI derives. Many of those are probably fine; the audit decides.
- **Reduce Motion:** `CoinFlipView.flip()` runs a 0.7 s spin (`withAnimation`) and six timed letter changes; `ScoreCorrectionSheet` uses `.contentTransition(.numericText())`. Neither checks `accessibilityReduceMotion`. (`HowToPlayView` does not animate: only a static rotated "KITCHEN" label; an earlier draft of this spec was wrong.)
- **Colour:** win/loss badges use green/red backgrounds but also carry a "W" or "L" letter (Home, History, Player detail; verified), so colour is not the only signal. A screen reader reads the bare letter "W" or "L", which is the gap. The point-by-point rows in `MatchDetailView` mark the scoring team with a small coloured dot but also print the team name, so that is fine visually but reads as four separate stops.
- **UI tests that constrain the fix:** the existing tests query `app.staticTexts[...]` by identifier for history rows ("Delon vs Katie", "Team A vs Team B"), manage-players rows ("PlayerRow.<name>", "Me.<name>") and the home record card ("Your Record", "1 - 0"). The score zone label must keep "<name>, <N> points" as its start (tests check `contains("12 points")` and parse the digits after the first ", ").
- **No automated accessibility audit exists** (no `performAccessibilityAudit` in the UI tests).

## Design

Four small pieces, in this order. Calls marked (my call) are mine, for the user to correct.

### 1. An automated audit first, as the measuring stick
Add `ServerTwoUITests/AccessibilityAuditUITests.swift` using XCUITest's `app.performAccessibilityAudit()` on each main screen: Home, Match setup, Coin flip, Scoring (including each prompt sheet where reachable), History list, Match detail, Players, Settings, How to Play, Onboarding, Paywall. (my call: start by listing findings; fix what is real; for findings that are false positives, ignore them one by one in an explicit issue handler with a comment saying why, never by turning categories off.) Run the audit once at the default text size and once at an accessibility text size (launch argument `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXL`; verified on the simulator: `simctl ui content_size accessibility-extra-extra-large` stores exactly that string, and it is accessibility size 4; `...XXXL` is size 5). Because a wrong string silently falls back to the default size, the accessibility-size test must also assert that the size really applied (for example a title's height is larger than at the default size). The audit catches clipped text, small touch targets (`.hitRegion`), missing descriptions and contrast. It does not catch reading order, rows that take four swipes, or state changes announced to VoiceOver.

**Staging (changed after review):** the audit test lands first in a report-only mode (it records every issue and prints the list, and passes), so it never leaves the suite red. The last task switches it to strict (any non-ignored issue fails). Likely real findings to fix in code rather than ignore: the `.controlSize(.small)` buttons in `HomeView` and `ManagePlayersView` (probably under 44 pt), white text on system orange/green/red badges (contrast, `MatchDetailView` and the W/L badges), the hidden `NavigationLink { EmptyView() }` in `ManagePlayersView`, and the stepper buttons in `ScoreCorrectionSheet`. These are expected candidates, not confirmed audit results.

### 2. Dynamic Type
- **Score digits:** switch the fixed sizes to scaled ones (`@ScaledMetric(relativeTo:)` on the size) so they grow with the user's setting, and cap growth on the biggest digits so a score never wraps (`.dynamicTypeSize(...DynamicTypeSize.accessibility2)` on the 108 pt digits; the cap number is my call and is adjusted by what the audit and a simulator look show). Either a `.dynamicTypeSize` cap or clamping the scaled value directly (`min(scaled, 128)`) is fine; the builder picks the one that keeps the team name and the "SERVING" badge scaling. Remove `minimumScaleFactor` where the text can wrap or the container can grow instead.
- **Sheets:** one shared helper modifier for presentation detents: the base height scaled with `@ScaledMetric`; the content in a `ScrollView` with `.scrollBounceBehavior(.basedOnSize)` so it is inert while the content fits; and `.large` added as a second detent ONLY when `dynamicTypeSize.isAccessibilitySize`. At normal sizes the sheets keep exactly one detent, so a small prompt can't be dragged to full screen and no new drag indicator appears. Apply it to the five fixed-height sheets. Note `FinishMatchSheet` and `ScoringPromptSheet` draw their own rounded card with `.presentationBackground(.clear)`; the scroll view goes inside that card and the card must keep filling the detent. The helper reads the size category from the environment; it does NOT measure the content and write that into state (that causes layout loops).
- **Icons and fixed-width columns:** make decorative icon frames and the 54-68 pt text columns scale with `@ScaledMetric`, or let the row stack vertically at accessibility sizes (`ViewThatFits` or `dynamicTypeSize.isAccessibilitySize`). Touch targets stay at least 44x44 pt.
- Layout at the default size must be pixel-for-pixel unchanged apart from rounding (checked by eye in the simulator against the current build).

### 3. VoiceOver
From the audit and a read of each screen, add only what is missing or wrong:
- **Score zone:** keep the label starting "<name>, <N> points"; append ", serving" when that team has the serve; move "Tap to score, or use the Actions rotor to correct the score." into `.accessibilityHint`. (Hints are not part of `XCUIElement.label`, so the existing tests keep working.) The default action and the "Correct score" action stay as they are.
- **Feedback while VoiceOver is on:** post `AccessibilityNotification.Announcement` with the same lines the Voice Announcer would speak (score call, side out, switch sides, game over, match over), because the announcer is silent under VoiceOver. This is decision Q4 below.
- **Coin flip and match end:** when the coin lands, post an announcement ("<name> serves first") and move VoiceOver focus to "Begin Match" (`@AccessibilityFocusState`), since the "Flip Coin" button disappears; when the match ends and "Finish Match" appears, move focus to it.
- Badges: the W/L badge reads "Won" / "Lost" (`.accessibilityLabel` on the badge itself). Do not combine whole rows that hold tested static texts (history rows, manage-players rows, the home record card); keep their identifiers on the same element types the tests query, or update the tests deliberately in the same task. The "recent form" strip on Home and Player detail becomes ONE element: label "Recent form", value "Won, Lost, Won, ...". The point-by-point rows in `MatchDetailView` combine into one stop each ("<name> scored, 4-2").
- explicit labels for icon-only buttons found by the audit; a header trait on section titles; hidden traits for purely decorative images.

### 4. Reduce Motion and colour
- Under `accessibilityReduceMotion` (`@Environment`), `CoinFlipView.flip()` skips the 3D spin and the six timed letter changes and calls `settle(on:)` straight away; the result and its probabilities are identical. `.contentTransition(.numericText())` in the correction sheet is replaced by no transition.
- Colour: the W/L badges already show a letter. Check the serving indicator (it has a text label "SERVING" plus a border, so it is fine) and any other state that is colour only; fix only what the audit or a read finds.

## Non-goals
- No change to scoring, rules, the announcer's wording, persistence or navigation.
- No localization, no new themes (a colourblind-safe theme is already a backlog item).
- Haptics, Switch Control, Voice Control, Full Keyboard Access and the Watch app are not part of this pass.
- No separate "large text layout" redesign: the goal is graceful scaling, not new screens.

## Edge cases and risks
- The score digits at the largest sizes: a 3-digit tie-break score ("12 - 10") must still fit on a phone in portrait; test at the cap.
- The `.large` second detent on prompt sheets: the Game Over sheet must still read in order and the primary button must stay reachable without scrolling at default size.
- UI tests query static texts by identifier or label (see the constraints above), so combining rows can break them. The full suite must stay green; where a test must change it changes in the same task, with its intent kept.
- The audit may report issues in system-provided UI; those are filtered explicitly, with a reason.

## Testing
- New: the audit UI tests (default size and one accessibility size), expected to pass with any ignored issue listed and justified.
- Unit tests only where logic is added (for example a pure helper that turns a match row into its spoken sentence).
- The full app suite and PickleballKit stay green; compile warning grep empty.
- Manual (user, on the phone): turn VoiceOver on and walk Home, a match, History and Settings; set text size to the largest accessibility setting and open every sheet; turn Reduce Motion on and flip the coin.

## Out of scope for now
Dark/light contrast tuning beyond what the audit flags; per-screen VoiceOver rotor actions; a spoken tutorial.

## Open questions with proposed defaults
1. **How large may the scoreboard digits grow?** Default: scale to the accessibility 2 size, then stop (no wrapping). A phone in portrait is the limit.
2. **Audit false positives.** Default: fix real ones, justify and ignore individual false positives one at a time; never disable a whole category.
3. **Split into two plans?** Default: one plan, four tasks, ordered so that every commit is green: (1) audit harness in report-only mode, (2) Dynamic Type and sheets, (3) VoiceOver (score zone serving, announcements and focus, badges and rows), (4) Reduce Motion and colour, then switch the audit to strict and fix what it still reports.
4. **Score feedback for VoiceOver users (needs the user's decision).** Today a VoiceOver user gets no spoken confirmation after scoring, because the announcer is silent under VoiceOver and the Voice Announcer setting is off by default. Default proposed: when VoiceOver is running, always post the short announcement for each change (score call, side out, switch sides, game and match end), regardless of the Voice Announcer toggle, because it is their only feedback; the toggle keeps controlling the spoken voice for everyone else.
5. **Dead code.** `CourtDiagramView.swift` is unused on the scoring screen. Default: leave it out of this pass (not an accessibility change) and mention it to the user; deleting it is a separate cleanup.
6. **Server number.** The scoring screen shows "SERVING" but not the doubles server number (1 or 2), for sighted users either. Default: out of scope here; VoiceOver gets exactly the information sighted users get.

## Review changes (Gemini review, 2026-10-18)
Accepted: UI-test constraints on combining rows; the serving gap and label/hint split on the score zone; `.scrollBounceBehavior(.basedOnSize)` and `.large` only at accessibility sizes; audit report-only first and strict last; expected audit failure sites; HowToPlay does not animate (my error), CoinFlip reduce-motion branch; announcements and focus for coin flip and match end; W/L letters confirmed; recent-form and point-row combining.
Rejected: Gemini said the launch argument `UICTContentSizeCategoryAccessibilityXXL` is wrong and that UIKit ignores it. Verified on the simulator that it is the exact string UIKit stores for accessibility size 4; the spec keeps it and adds a check that the size really applied.
