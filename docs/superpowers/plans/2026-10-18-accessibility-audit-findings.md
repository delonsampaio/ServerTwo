# Accessibility audit findings (report-only baseline)

Source: `ServerTwoUITests/AccessibilityAuditUITests` (`app.performAccessibilityAudit()`, report-only), run 2026-10-18 on simulator 3C7D4B7A (iPhone 17 Pro, iOS 27.0), default content size `large` unless the screen is marked `@AXXL` (`UICTContentSizeCategoryAccessibilityXXL`). Rows are copied verbatim from the `A11Y-AUDIT|` log lines of that run. This file is the work list for Tasks 2-5.

Total: 141 issues across 14 audited screens. `(no element)` means the audit reported no element for the issue. `label:` prefixes mean the element has no accessibility identifier and its label is shown instead.

## Summary

| Screen | Issues |
|---|---|
| Onboarding | 8 |
| Home | 2 |
| MatchSetup | 11 |
| CoinFlip | 12 |
| Scoring | 17 |
| CancelMatchPrompt | 11 |
| History | 3 |
| MatchDetail | 31 |
| Settings | 7 |
| ManagePlayers | 0 |
| HowToPlay | 5 |
| Paywall | 8 |
| Scoring@AXXL | 17 |
| CancelMatchPrompt@AXXL | 9 |

## Onboarding

| Screen | Audit type | Element | Description |
|---|---|---|---|
| Onboarding | contrast | Done | Contrast failed |
| Onboarding | contrast | label:Score singles and doubles matches point by point. Server Two keeps track of who's serving, which side everyone's on, and your stats over time. | Contrast nearly passed |
| Onboarding | contrast | label:Set this once so your personal win/loss record starts tracking automatically. | Contrast nearly passed |
| Onboarding | contrast | Get Started | Contrast failed |
| Onboarding | contrast | label:Always know which partner belongs on the left or right court. | Contrast nearly passed |
| Onboarding | contrast | label:Tap a card to score a point, or press and hold to fix a disputed score. | Contrast nearly passed |
| Onboarding | contrast | label:See your record with every partner and against every rival. | Contrast nearly passed |
| Onboarding | dynamicType | Done | Dynamic Type font sizes are partially unsupported |

## Home

| Screen | Audit type | Element | Description |
|---|---|---|---|
| Home | contrast | label:New Match | Contrast failed |
| Home | contrast | label:Play your first match to see it here. | Contrast nearly passed |

## MatchSetup

| Screen | Audit type | Element | Description |
|---|---|---|---|
| MatchSetup | hitRegion | (no element) | Hit area is too small |
| MatchSetup | hitRegion | (no element) | Hit area is too small |
| MatchSetup | hitRegion | Log Final Score Instead | Hit area is too small |
| MatchSetup | contrast | Start Match | Contrast failed |
| MatchSetup | contrast | Log Final Score Instead | Contrast nearly passed |
| MatchSetup | contrast | (no element) | Contrast nearly passed |
| MatchSetup | contrast | (no element) | Contrast nearly passed |
| MatchSetup | contrast | (no element) | Contrast nearly passed |
| MatchSetup | contrast | (no element) | Contrast nearly passed |
| MatchSetup | contrast | (no element) | Contrast nearly passed |
| MatchSetup | contrast | (no element) | Contrast nearly passed |

## CoinFlip

| Screen | Audit type | Element | Description |
|---|---|---|---|
| CoinFlip | contrast | Cancel Coin Flip | Contrast failed |
| CoinFlip | contrast | FirstServeResult | Contrast nearly passed |
| CoinFlip | contrast | Flip Coin | Contrast nearly passed |
| CoinFlip | contrast | label:Already spun a paddle? | Contrast failed |
| CoinFlip | contrast | Team A Won Spin | Contrast nearly passed |
| CoinFlip | contrast | Team B Won Spin | Contrast nearly passed |
| CoinFlip | dynamicType | Cancel Coin Flip | Dynamic Type font sizes are partially unsupported |
| CoinFlip | textClipped | label:Already spun a paddle? | Text clipped |
| CoinFlip | textClipped | Team A Won Spin | Text clipped |
| CoinFlip | textClipped | label:Team A vs Team B | Text clipped |
| CoinFlip | textClipped | Team B Won Spin | Text clipped |
| CoinFlip | textClipped | FirstServeResult | Text clipped |

## Scoring

| Screen | Audit type | Element | Description |
|---|---|---|---|
| Scoring | contrast | Cancel Match | Contrast failed |
| Scoring | contrast | label:SERVING | Contrast failed |
| Scoring | contrast | label:Tap to Score | Contrast failed |
| Scoring | contrast | label:Tap to Score | Contrast failed |
| Scoring | contrast | label:Timeout (2) | Contrast failed |
| Scoring | contrast | label:Timeout (2) | Contrast failed |
| Scoring | dynamicType | label:Tap to Score | Dynamic Type font sizes are partially unsupported |
| Scoring | dynamicType | label:Tap to Score | Dynamic Type font sizes are partially unsupported |
| Scoring | dynamicType | Cancel Match | Dynamic Type font sizes are partially unsupported |
| Scoring | dynamicType | label:0 | Dynamic Type font sizes are unsupported |
| Scoring | dynamicType | label:0 | Dynamic Type font sizes are unsupported |
| Scoring | textClipped | label:Tap to Score | Text clipped |
| Scoring | textClipped | label:SERVING | Text clipped |
| Scoring | textClipped | label:Team A vs Team B | Text clipped |
| Scoring | textClipped | label:Tap to Score | Text clipped |
| Scoring | textClipped | label:Timeout (2) | Text clipped |
| Scoring | textClipped | label:Timeout (2) | Text clipped |

## CancelMatchPrompt

| Screen | Audit type | Element | Description |
|---|---|---|---|
| CancelMatchPrompt | contrast | label:Current game 0 – 0 | Contrast failed |
| CancelMatchPrompt | contrast | label:This can't be undone. | Contrast failed |
| CancelMatchPrompt | contrast | Prompt.KeepPlaying | Contrast failed |
| CancelMatchPrompt | contrast | Confirm Cancel Match | Contrast failed |
| CancelMatchPrompt | elementDetection | (no element) | Potentially inaccessible text |
| CancelMatchPrompt | textClipped | label:This can't be undone. | Text clipped |
| CancelMatchPrompt | textClipped | Prompt.KeepPlaying | Text clipped |
| CancelMatchPrompt | textClipped | label:Team A vs Team B | Text clipped |
| CancelMatchPrompt | textClipped | label:Cancel this match? | Text clipped |
| CancelMatchPrompt | textClipped | label:Current game 0 – 0 | Text clipped |
| CancelMatchPrompt | textClipped | Confirm Cancel Match | Text clipped |

## History

| Screen | Audit type | Element | Description |
|---|---|---|---|
| History | contrast | label:Matches | Contrast nearly passed |
| History | contrast | label:Matches | Contrast nearly passed |
| History | contrast | label:October 18, 2026 | Contrast nearly passed |

## MatchDetail

| Screen | Audit type | Element | Description |
|---|---|---|---|
| MatchDetail | contrast | Rematch | Contrast failed |
| MatchDetail | contrast | label:October 18, 2026 | Contrast failed |
| MatchDetail | contrast | label:Doubles • Best of 1 • < 1 min | Contrast failed |
| MatchDetail | contrast | label:Team A | Contrast failed |
| MatchDetail | contrast | label:Team B | Contrast failed |
| MatchDetail | contrast | label:0 | Contrast failed |
| MatchDetail | contrast | label:1 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:2 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:3 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:4 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:5 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:6 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:7 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:8 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:9 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:10 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | contrast | label:11 | Contrast failed |
| MatchDetail | contrast | label:Team A scored | Contrast failed |
| MatchDetail | dynamicType | label:0 | Dynamic Type font sizes are unsupported |
| MatchDetail | dynamicType | label:11 | Dynamic Type font sizes are unsupported |
| MatchDetail | dynamicType | Rematch | Dynamic Type font sizes are partially unsupported |

## Settings

| Screen | Audit type | Element | Description |
|---|---|---|---|
| Settings | contrast | (no element) | Contrast nearly passed |
| Settings | contrast | (no element) | Contrast nearly passed |
| Settings | contrast | (no element) | Contrast nearly passed |
| Settings | contrast | (no element) | Contrast nearly passed |
| Settings | contrast | (no element) | Contrast nearly passed |
| Settings | textClipped | label:Haptics | Text clipped |
| Settings | textClipped | (no element) | Text clipped |

## ManagePlayers

No issues reported.

## HowToPlay

| Screen | Audit type | Element | Description |
|---|---|---|---|
| HowToPlay | contrast | label:A quick reference for pickleball's core rules — serving, scoring, and the two rules that trip up most beginners. | Contrast nearly passed |
| HowToPlay | contrast | label:All lines are in — including the serve's sideline, centerline, and baseline. The one exception is the kitchen line, which is out on a serve. | Contrast failed |
| HowToPlay | contrast | label:A serve that clips the net but still lands in the correct box is live play, not a replay — that changed in 2021. | Contrast failed |
| HowToPlay | contrast | label:The Two-Bounce Rule | Contrast failed |
| HowToPlay | contrast | label:After the serve, the receiving side must let the ball bounce before returning it — and the serving side must let that return bounce too. Only after both of those bounces can either side start volleying (hitting the ball out of the air). This is what stops a team from serving and immediately rushing the net to end the point. | Contrast failed |

## Paywall

| Screen | Audit type | Element | Description |
|---|---|---|---|
| Paywall | contrast | Not Now | Contrast failed |
| Paywall | contrast | label:The free version lets you play 1 full match, start to finish. Unlock Server Two Pro for a one-time $1.99 to play unlimited matches, forever. | Contrast nearly passed |
| Paywall | contrast | Unlock Pro — $1.99 | Contrast nearly passed |
| Paywall | contrast | label:Restore Purchases | Contrast nearly passed |
| Paywall | dynamicType | Not Now | Dynamic Type font sizes are partially unsupported |
| Paywall | textClipped | label:You've Reached the Free Demo Limit | Text clipped |
| Paywall | textClipped | Unlock Pro — $1.99 | Text clipped |
| Paywall | textClipped | label:The free version lets you play 1 full match, start to finish. Unlock Server Two Pro for a one-time $1.99 to play unlimited matches, forever. | Text clipped |

## Scoring@AXXL

| Screen | Audit type | Element | Description |
|---|---|---|---|
| Scoring@AXXL | contrast | Cancel Match | Contrast failed |
| Scoring@AXXL | contrast | label:Tap to Score | Contrast failed |
| Scoring@AXXL | contrast | label:SERVING | Contrast failed |
| Scoring@AXXL | contrast | label:Tap to Score | Contrast failed |
| Scoring@AXXL | contrast | label:Timeout (2) | Contrast failed |
| Scoring@AXXL | contrast | label:Timeout (2) | Contrast failed |
| Scoring@AXXL | dynamicType | label:0 | Dynamic Type font sizes are unsupported |
| Scoring@AXXL | dynamicType | label:0 | Dynamic Type font sizes are unsupported |
| Scoring@AXXL | dynamicType | label:Tap to Score | Dynamic Type font sizes are partially unsupported |
| Scoring@AXXL | dynamicType | Cancel Match | Dynamic Type font sizes are partially unsupported |
| Scoring@AXXL | dynamicType | label:Tap to Score | Dynamic Type font sizes are partially unsupported |
| Scoring@AXXL | textClipped | label:Timeout (2) | Text clipped |
| Scoring@AXXL | textClipped | label:Tap to Score | Text clipped |
| Scoring@AXXL | textClipped | label:Timeout (2) | Text clipped |
| Scoring@AXXL | textClipped | label:SERVING | Text clipped |
| Scoring@AXXL | textClipped | label:Team A vs Team B | Text clipped |
| Scoring@AXXL | textClipped | label:Tap to Score | Text clipped |

## CancelMatchPrompt@AXXL

| Screen | Audit type | Element | Description |
|---|---|---|---|
| CancelMatchPrompt@AXXL | contrast | label:Current game 0 – 0 | Contrast failed |
| CancelMatchPrompt@AXXL | contrast | label:This can't be undone. | Contrast failed |
| CancelMatchPrompt@AXXL | contrast | Confirm Cancel Match | Contrast failed |
| CancelMatchPrompt@AXXL | textClipped | label:Current game 0 – 0 | Text clipped |
| CancelMatchPrompt@AXXL | textClipped | Prompt.KeepPlaying | Text clipped |
| CancelMatchPrompt@AXXL | textClipped | Confirm Cancel Match | Text clipped |
| CancelMatchPrompt@AXXL | textClipped | label:Cancel this match? | Text clipped |
| CancelMatchPrompt@AXXL | textClipped | label:This can't be undone. | Text clipped |
| CancelMatchPrompt@AXXL | textClipped | label:Team A vs Team B | Text clipped |
## Observations

These are judgements from reading the log only; nothing was visually verified on a device yet. Verify each before fixing.

**Coverage limits of this baseline**
- Every test launches with `-UITest-ResetState`, so Home was audited in its empty state ("Play your first match to see it here."): the Last Match card, Your Record, RecentForm, quick-start row and the Home unlock banner were NOT audited. Manage Players was audited with an empty list (0 issues means "nothing to audit", not "clean"). Later tasks that change those views should extend the harness to audit them with data (for example after `playAndFinishOneMatch`).
- Results are not perfectly stable between runs: `CancelMatchPrompt@AXXL` reported 10 issues in the first run and 9 in the final one (one fewer contrast row). Do not treat a count as an exact baseline.
- The accessibility-size launch argument was verified to take effect: the coin-flip subtitle `FirstServeResult` is 18.0 pt tall at the default size and 50.3 pt tall at AccessibilityXXL.

**Likely real**
- `dynamicType` on `label:0` / `label:11` (score digits on Scoring and the match-detail score) reported "unsupported": the score numbers use a fixed-size font. Also `label:Tap to Score`, `Cancel Match`, `Cancel Coin Flip`, `Done`, `Not Now`, `Rematch` ("partially unsupported"). These match the accessibility-size work planned in later tasks.
- `textClipped` at AccessibilityXXL on the Cancel Match prompt (title, body, both buttons) and on Scoring (`Timeout (2)`, `SERVING`, `Tap to Score`): plausible real clipping at large sizes.
- `hitRegion` on MatchSetup: `Log Final Score Instead` ("Hit area is too small") plus two issues with no element. Real against the 44 x 44 pt rule.
- `contrast` "failed" on primary controls that sit on the accent colour or on filled backgrounds: `Start Match`, `New Match`, `Done`, `Get Started`, `Rematch`, `Cancel Match` (toolbar), `Not Now`, `Prompt.KeepPlaying`, `Confirm Cancel Match`. Likely real, since white text on the accent colour is a known borderline pairing.

**Likely false positives or needing verification**
- MatchDetail contrast: 31 issues, almost all "Contrast failed", including every point-by-point row (`Team A scored`, the running score digits). The uniformity suggests the audit is sampling a background (for example a material or gradient behind the list) incorrectly. Verify visually before changing colours.
- All "Contrast nearly passed" items (secondary-label text on Home, History, Settings, MatchSetup, Onboarding, Paywall; the five `(no element)` rows on Settings and the seven on MatchSetup): these are borderline and often caused by `.secondary` text over grouped-list backgrounds. Low priority.
- `textClipped` at the default size on `Team A vs Team B` (CoinFlip, Scoring), `Team A Won Spin`, `Team B Won Spin`, `FirstServeResult`, `Already spun a paddle?`, `Haptics`, and the Paywall title/body/button: the text is short and fits at default size, so these look like false positives caused by tight frames or the audit's text-measurement; check at the default size by eye.
- `elementDetection` "Potentially inaccessible text" with no element on the Cancel Match prompt (reported at both sizes): cannot be attributed to a view from the log; check whether the prompt has text rendered outside an accessibility element.
- `Settings` `(no element)` `textClipped`: no element reported, so it cannot be located from the log alone.
