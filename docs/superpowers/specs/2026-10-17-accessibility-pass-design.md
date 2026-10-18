# Accessibility Pass Design (Phase 7)

**Date:** 2026-10-17
**Status:** Draft, awaiting Gemini review and user approval
**Builds on:** Phase 7 "Audio & Accessibility" on the roadmap (the Voice Announcer half is already built)

## Goal

Make every screen of the app usable (1) at the largest Dynamic Type sizes, (2) with VoiceOver, (3) with Reduce Motion on, and (4) without relying on colour alone. No new features, no rules or scoring changes, no visual redesign at the default text size.

Pickleball is played outdoors, one-handed, often at arm's length, so large readable text is a core need and not only an accessibility nicety. The scoreboard digits stay the biggest thing on the screen at every setting.

## What the code does today (verified by reading the source, 2026-10-17)

- **VoiceOver, already good on the scoring screen:** each score zone is one element with a button trait, a label ("<name>, <n> points. Tap to score, double tap and hold to correct."), a default action and a named "Correct score" action (`ScoringView.swift` ~429-440). The court diagram carries a full spoken description. The timeout buttons, Undo, the Score Correction sheet (steppers with labels and values), the prompt sheets (containers, header trait) and onboarding (decorative images hidden) have labels.
- **The Voice Announcer is silent while VoiceOver runs** (`VoiceAnnouncer.swift:27`, tested), so the two never talk over each other.
- **Dynamic Type gaps:**
  - 15 fixed `.font(.system(size: ...))` uses: the big score digits (108 pt in `ScoringView`, 64 pt in the correction and prompt sheets, 36-48 pt elsewhere), coin flip, paywall, onboarding, avatar initials.
  - Fixed-height sheets: `ManagePlayersView` rename and add sheets `.height(180)` (two places), `FinishMatchSheet` `.height(320)`, `ScoreCorrectionSheet` `.height(360)` plus `.large`, `ScoringPromptSheet` `.height(detentHeight)`.
  - Fixed-size icons and badges (22x22, 28x28, 53x53, 60x60 frames) and fixed-width text columns (54, 56, 68 pt) in History, Home, Player detail and Match setup.
  - `minimumScaleFactor` is used as a shrink-to-fit on score columns (0.6-0.85), which makes text smaller at the sizes where people need it larger.
- **Accessibility labels are sparse outside the scoring flow:** Home, History, Players, Settings, Match setup, Coin flip, Paywall and the recap share button have no explicit labels or hints, so VoiceOver reads whatever SwiftUI derives. Many of those are probably fine; the audit decides.
- **Reduce Motion:** `HowToPlayView` and `CoinFlipView` animate; neither checks `accessibilityReduceMotion`.
- **Colour:** win/loss badges use green/red backgrounds (Home, History, Player detail). Whether each also carries a letter or symbol is unconfirmed.
- **No automated accessibility audit exists** (no `performAccessibilityAudit` in the UI tests).

## Design

Four small pieces, in this order. Calls marked (my call) are mine, for the user to correct.

### 1. An automated audit first, as the measuring stick
Add `ServerTwoUITests/AccessibilityAuditUITests.swift` using XCUITest's `app.performAccessibilityAudit()` on each main screen: Home, Match setup, Coin flip, Scoring (including each prompt sheet where reachable), History list, Match detail, Players, Settings, How to Play, Onboarding, Paywall. (my call: start by listing findings; fix what is real; for findings that are false positives, ignore them one by one in an explicit issue handler with a comment saying why, never by turning categories off.) Run the audit once at the default text size and once at an accessibility text size (launch argument `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXL`). The audit catches clipped text, small touch targets, missing descriptions and contrast. It does not replace a VoiceOver listen-through by the user.

### 2. Dynamic Type
- **Score digits:** switch the fixed sizes to scaled ones (`@ScaledMetric(relativeTo:)` on the size) so they grow with the user's setting, and cap growth on the biggest digits so a score never wraps (`.dynamicTypeSize(...DynamicTypeSize.accessibility2)` on the 108 pt digits; the cap number is my call and is adjusted by what the audit and a simulator look show). Remove `minimumScaleFactor` where the text can wrap or the container can grow instead.
- **Sheets:** one shared helper modifier for presentation detents: the base height scaled with `@ScaledMetric`, plus `.large` as a second detent, with the content in a `ScrollView` so nothing is ever unreachable. Apply it to the five fixed-height sheets. The helper reads the size category from the environment; it does NOT measure the content and write that into state (that causes layout loops).
- **Icons and fixed-width columns:** make decorative icon frames and the 54-68 pt text columns scale with `@ScaledMetric`, or let the row stack vertically at accessibility sizes (`ViewThatFits` or `dynamicTypeSize.isAccessibilitySize`). Touch targets stay at least 44x44 pt.
- Layout at the default size must be pixel-for-pixel unchanged apart from rounding (checked by eye in the simulator against the current build).

### 3. VoiceOver
From the audit and a read of each screen, add only what is missing or wrong:
- explicit labels for icon-only buttons, and values for rows that read as unrelated fragments (a history row should read as one sentence: "Won 11-7 against Fred, October 14");
- `.accessibilityElement(children: .combine)` on cards and rows that read as many stops;
- a header trait on section titles; hidden traits for purely decorative images;
- the win/loss badge announces "won" / "lost" in words (not just a letter or colour).
No change to the score zone, which is already correct.

### 4. Reduce Motion and colour
- Under `accessibilityReduceMotion`, replace the coin flip's spin and the How to Play animation with a cross-fade or an instant change. The coin flip result stays identical.
- Win/loss: confirm each badge also shows a letter or symbol; where it is colour only, add one. Check the serving indicator and any other state that is colour only.

## Non-goals
- No change to scoring, rules, the announcer's wording, persistence or navigation.
- No localization, no new themes (a colourblind-safe theme is already a backlog item).
- Haptics, Switch Control, Voice Control, Full Keyboard Access and the Watch app are not part of this pass.
- No separate "large text layout" redesign: the goal is graceful scaling, not new screens.

## Edge cases and risks
- The score digits at the largest sizes: a 3-digit tie-break score ("12 - 10") must still fit on a phone in portrait; test at the cap.
- The `.large` second detent on prompt sheets: the Game Over sheet must still read in order and the primary button must stay reachable without scrolling at default size.
- UI tests find elements by accessibility identifier, not by label, so label changes should not break them; the label of the score zone is not touched. The full suite must stay green.
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
3. **Split into two plans?** Default: one plan, four tasks (audit harness, Dynamic Type, VoiceOver, Reduce Motion and colour), because each task is small and the audit measures the others.
