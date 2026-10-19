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

## As built (2026-10-18)

### What changed, per task
1. **Audit harness (report-only).** `AccessibilityAuditUITests` runs `performAccessibilityAudit` on every main screen (Onboarding, Home empty / with a match / with a match and a Me player, Match Setup, Coin Flip, Scoring, Cancel Match prompt, History, Match Detail, Settings, Manage Players empty / with rows, How to Play, Paywall) and at accessibility size 4 (`UICTContentSizeCategoryAccessibilityXXL`). Each audit waits for a hittable anchor and a 0.5 s settle; findings are logged as `A11Y-AUDIT|...` lines and attached to the test. The baseline is `docs/superpowers/plans/2026-10-18-accessibility-audit-findings.md`.
2. **Dynamic Type and sheets.** Scaled fonts and metrics (`@ScaledMetric`, capped where the layout needs it), `AdaptiveStack` (row at normal sizes, column at accessibility sizes), `AdaptiveScroll` and `adaptiveSheetDetents` (`.large` only at accessibility sizes), `PillButtonStyle` (44 pt hit region with the old pill look), stacked timeout and Won Spin buttons at accessibility sizes. Several secondary texts moved to `.primary` for contrast (Match Detail summary lines, Coin Flip and Cancel prompt captions, "Tap to Score" to `.secondary`).
3. **VoiceOver announcement path.** `VoiceOverAnnouncement` (one place, high priority); with VoiceOver running the score lines are always announced regardless of the Voice Announcer toggle, and the synthesizer voice is never used.
4. **VoiceOver labels, values and focus.** `AccessibilityText` (score zone label "<name>, <N> points[, serving]" plus a hint, Won/Lost words, recent form value, point row sentences), grouped recent-form strips and point rows, header traits, decorative glyphs hidden, "Begin Match" and "Finish Match" take focus, the coin flip result is announced.
5. **Reduce Motion, sheet checks, final pass.** `CoinFlipAnimationPlan` (normal: spin, 6 letter toggles, 0.7 s settle; Reduce Motion: no spin, no toggles, immediate settle, `isFlipping` never set so it cannot stick); `CoinFlipView.flip()` reads it from `accessibilityReduceMotion`. `ScoreCorrectionSheet` uses `.contentTransition(reduceMotion ? .identity : .numericText())`. The audit class gained `testSheetsAtAccessibilitySize` (Game Over sheet of a best of 3 and the Finish Match sheet of a best of 1, both at accessibility size 4, primary buttons asserted hittable, each audited as `GameOverSheet@AXXL` and `FinishMatchSheet@AXXL`), and `KnownFalsePositive` now refuses an empty `descriptionContains` so an entry can never act as a wildcard.

### Strict audit: on, with documented exceptions
`strict = true`. Every issue the audit reports must match an entry of `AccessibilityAuditExceptions.all` (`ServerTwoUITests/AccessibilityAuditExceptions.swift`): screen, audit type, one of the entry's element names, a description substring (`KnownFalsePositive` refuses an empty one) and an occurrence cap per audit of the screen. There is no whole-category or whole-screen wildcard. The audit does not name elements consistently (the same issue is attributed to an element in one run and to "(no element)" in another, and its detailed description is generic), so each entry lists every element name it has been seen under plus "(no element)", and the cap makes an extra or new issue fail. Date labels are normalised to `label:<date>`.

The final report-only run had 125 issues. After the code fixes below they are covered by 40 entries (133 permitted occurrences, 141 element names):

| Reason | Entries | What it covers |
|---|---|---|
| False positive: static textClipped heuristic | 5 | Identical at default size and AX4 on Scoring, Cancel Match prompt, Settings, Manage Players; screenshots at default and AX4 show nothing clipped |
| False positive: text behind a sheet | 1 | Cancel Match prompt "Potentially inaccessible text": the scoring text visible behind the presented sheet (also reported for the Game Over sheet at default size); the sheet badge was ruled out |
| Dynamic Type "partially unsupported" | 6 | Score digits and "Tap to Score" (scale with a cap), "SERVING" (capped at accessibility1), system toolbar text, rows that reflow at accessibility sizes; text visibly scales and is not clipped at AX4 |
| design decision pending: accent blue and toolbar buttons | 10 | 4.02:1 white-on-accent or accent text, system toolbar buttons |
| design decision pending: accent blue + secondary captions | 3 | Coin Flip, Home with a match, Paywall |
| design decision pending: secondary captions | 6 | `.secondary` text on grouped or material backgrounds, 3.4 to 4.4:1 |
| design decision pending: How to Play text | 2 | `.secondary` body and headings |
| design decision pending: Home with a Me player | 2 | accent 4.02:1, white on green 2.22:1, W/L tints, avatar palette |
| design decision pending: avatars, Me badge, pills | 2 | per-run avatar colour, Me badge, Rename / Set as Me pills |
| design decision pending: Match Detail sequence numbers | 1 | `.tertiary` sequence numbers, loser digit, Rematch |
| design decision pending: Game Over / Finish Match sheets at AX4 | 2 | `.secondary` lines and loser digit, accent button |

So 12 of the 40 entries are verified false positives or system behaviour and 28 are "design decision pending" colour items (no colour was changed).

Run status: the audit class passed all 11 tests, with no unexpected issue, in several full runs (the final exception file in runs 15 and 17; earlier file versions in runs 9 and 10). Three consecutive fully clean runs were not obtained: on this machine (heavy host load, memory pressure) XCUITest regularly stalls for about 15 minutes ("Timed out while synthesizing event", "Timed out while running accessibility audit", an anchor that never becomes hittable) in a different test each run, in non-audit UI classes too. Every failing run was infrastructure, not an audit finding; the full suite ended 206 of 207 passed with that kind of stall in `testScoring`, which passed on a rerun (see the Task 5 report).

### Real findings fixed along the way
- Task 2: both decorative `chevron.right` hit-region rows (hidden from accessibility), several textClipped heuristics (content now scrolls or wraps), Rename / Set as Me / Home share button tap targets (44 pt, measured 46.3 pt and 44 x 48.7 pt), pills, sheets that clipped at accessibility sizes.
- Task 2 follow-up: contrast fixes listed under task 2 above.
- Task 4: the recent-form strip and point rows no longer read letter by letter.
- Task 5: three real hit-area findings fixed in code. Match Setup "Swap Partners" and "Swap Teams" were 108 x 16 and 98 x 14 pt (now a 44 pt tall tap area through `tapAreaLabel()` on the label and `tapAreaGiveBack()` on the Button, same technique as `PillButtonStyle`, layout unchanged), and the "Me" badge on Manage Players was a small hit region (`tapAreaPadding()`). The "Potentially inaccessible text" row on the Cancel Match prompt is background text behind the sheet (see above), not a defect. The two new sheet checks found no unreachable buttons at accessibility size 4. Observed but not flagged by the audit (not in a screen it covers at AX4): the large title "Manage Players" truncates to "Manage Play..." at accessibility size 4.

### Colour items awaiting a design decision (light mode; WCAG, white text unless noted)
- Accent blue #007AFF as text or white-on-accent (Start Match, New Match, Done, Get Started, Keep Playing, Confirm Finish, Rematch / Rename / Set as Me pills, "SERVING" badge, Timeout buttons, Home Pro banner): 4.02:1, needs 4.5:1 for small text. Fix: a darker accent.
- White on green #34C759 (recent-form dots, W badges): 2.22:1; green or red text on a 20 % tinted circle (W / L badges) fails. Closest / Longest Game badges: white on orange 2.20:1, white on blue 4.02:1. Win streak orange text on the card is low.
- Avatar initials (white): teal 2.57, orange 2.20, mint 2.12, brown 3.50, pink 3.65, blue 4.02, purple 4.13 (indigo 5.65 passes). Black initials would pass for teal, orange and mint (8.2, 9.6, 9.9). The colour is assigned per player, so avatar rows vary between runs.
- Match Detail: point sequence numbers (`.tertiary` caption on thin material, needs `.primary`) and the losing team's digit (36 pt bold `.secondary`; the emphasis is the design).
- System toolbar buttons (Cancel Match, Cancel Coin Flip, Done, Not Now, Rematch): no styling hook.
- "Nearly passed" `.secondary` captions (about 3.4 to 4.4:1 on grouped or thin material): onboarding captions, Settings footers, Match Setup captions, Coin Flip and History captions, Paywall and How to Play body text.

### Device checks owed (for the user, after the build)
- VoiceOver on: scoring screen reads "<name>, <N> points, serving" for the serving team only; double-tap scores; the new score / side out / game end is spoken once (watch for double reading: VoiceOver re-reading the label PLUS our announcement; if it doubles, report it); flip the coin: announcement and focus lands on Begin Match; match over: focus lands on Finish Match; history row, recent form and point rows read as single sensible stops.
- Voice Announcer toggle OFF with VoiceOver on: scores are still announced; VoiceOver off with the toggle off: silent.
- Text size at the largest accessibility setting: open Home, Play, History, Settings, Manage Players, Add/Rename Player, the scoring screen (two-digit scores), Game Over, Switch Sides, Cancel Match, Score Correction and Finish Match sheets: nothing clipped, every button reachable.
- Reduce Motion on: the coin flip settles instantly with the same result.
