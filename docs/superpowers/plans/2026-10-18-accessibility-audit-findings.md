# Accessibility audit findings (report-only baseline)

Source: `ServerTwoUITests/AccessibilityAuditUITests` (`app.performAccessibilityAudit()`, report-only), final run (second of two consecutive runs) on 2026-10-18 on simulator 3C7D4B7A (iPhone 17 Pro, iOS 27.0), default content size `large` unless the screen is marked `@AXXL` (`UICTContentSizeCategoryAccessibilityXXL`). Each audit waits for a hittable anchor element and a 0.5 s settle first. Rows are copied verbatim from the `A11Y-AUDIT|` log lines of that run (compact and detailed descriptions). This file is the work list for Tasks 2-5.

Total: 170 issues across 17 audited screens. `(no element)` means the audit reported no element for the issue. `label:` prefixes mean the element has no accessibility identifier and its label is shown instead.

## Summary

| Screen | Issues |
|---|---|
| Onboarding | 8 |
| Home | 2 |
| HomeWithMatch | 3 |
| HomeWithMatchAndMe | 14 |
| MatchSetup | 11 |
| CoinFlip | 12 |
| Scoring | 17 |
| CancelMatchPrompt | 11 |
| History | 3 |
| MatchDetail | 31 |
| Settings | 7 |
| ManagePlayers | 0 (empty state only, no players saved) |
| ManagePlayersWithRows | 12 |
| HowToPlay | 5 |
| Paywall | 8 |
| Scoring@AXXL | 17 |
| CancelMatchPrompt@AXXL | 9 |

## Onboarding

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| Onboarding | contrast | Done | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Onboarding | contrast | label:Score singles and doubles matches point by point. Server Two keeps track of who's serving, which side everyone's on, and your stats over time. | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Onboarding | contrast | label:Set this once so your personal win/loss record starts tracking automatically. | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Onboarding | contrast | Get Started | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Onboarding | contrast | label:Always know which partner belongs on the left or right court. | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Onboarding | contrast | label:Tap a card to score a point, or press and hold to fix a disputed score. | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Onboarding | contrast | label:See your record with every partner and against every rival. | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Onboarding | dynamicType | Done | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |

## Home

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| Home | contrast | label:New Match | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Home | contrast | label:Play your first match to see it here. | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |

## HomeWithMatch

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| HomeWithMatch | contrast | label:New Match | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| HomeWithMatch | contrast | Rematch | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| HomeWithMatch | contrast | label:Unlock Server Two Pro — $1.99 | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |

## HomeWithMatchAndMe

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| HomeWithMatchAndMe | contrast | label:New Match | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | contrast | Rematch | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| HomeWithMatchAndMe | contrast | label:W | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | contrast | WinStreak | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | contrast | RecentForm | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | contrast | label:A | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| HomeWithMatchAndMe | contrast | label:B | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| HomeWithMatchAndMe | contrast | label:Unlock Server Two Pro — $1.99 | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| HomeWithMatchAndMe | dynamicType | label:Bob | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | dynamicType | label:A | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | dynamicType | label:W | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | dynamicType | label:B | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | dynamicType | label:Alice | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| HomeWithMatchAndMe | textClipped | WinStreak | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |

## MatchSetup

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| MatchSetup | hitRegion | (no element) | Hit area is too small | The size of this SwiftUI.AccessibilityNode is too small for user to interact. |
| MatchSetup | hitRegion | (no element) | Hit area is too small | The size of this SwiftUI.AccessibilityNode is too small for user to interact. |
| MatchSetup | hitRegion | Log Final Score Instead | Hit area is too small | The size of this SwiftUI.AccessibilityNode is too small for user to interact. |
| MatchSetup | contrast | Start Match | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchSetup | contrast | Log Final Score Instead | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| MatchSetup | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| MatchSetup | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| MatchSetup | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| MatchSetup | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| MatchSetup | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| MatchSetup | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |

## CoinFlip

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| CoinFlip | contrast | Cancel Coin Flip | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CoinFlip | contrast | FirstServeResult | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| CoinFlip | contrast | Flip Coin | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| CoinFlip | contrast | label:Already spun a paddle? | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CoinFlip | contrast | Team A Won Spin | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| CoinFlip | contrast | Team B Won Spin | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| CoinFlip | dynamicType | Cancel Coin Flip | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| CoinFlip | textClipped | Team A Won Spin | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CoinFlip | textClipped | label:Already spun a paddle? | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CoinFlip | textClipped | label:Team A vs Team B | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CoinFlip | textClipped | Team B Won Spin | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CoinFlip | textClipped | FirstServeResult | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |

## Scoring

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| Scoring | contrast | Cancel Match | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring | contrast | label:SERVING | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring | contrast | label:Tap to Score | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring | contrast | label:Tap to Score | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring | contrast | label:Timeout (2) | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring | contrast | label:Timeout (2) | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring | dynamicType | label:Tap to Score | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring | dynamicType | Cancel Match | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring | dynamicType | label:Tap to Score | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring | dynamicType | label:0 | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring | dynamicType | label:0 | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring | textClipped | label:Tap to Score | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring | textClipped | label:SERVING | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring | textClipped | label:Timeout (2) | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring | textClipped | label:Timeout (2) | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring | textClipped | label:Tap to Score | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring | textClipped | label:Team A vs Team B | Text clipped | Text of this UILabel may be clipped at larger Dynamic Type sizes. |

## CancelMatchPrompt

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| CancelMatchPrompt | contrast | label:Current game 0 – 0 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CancelMatchPrompt | contrast | label:This can't be undone. | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CancelMatchPrompt | contrast | Prompt.KeepPlaying | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CancelMatchPrompt | contrast | Confirm Cancel Match | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CancelMatchPrompt | elementDetection | (no element) | Potentially inaccessible text | This element appears to display text that should be represented using the accessibility API. |
| CancelMatchPrompt | textClipped | label:Team A vs Team B | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt | textClipped | label:Cancel this match? | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt | textClipped | label:Current game 0 – 0 | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt | textClipped | Confirm Cancel Match | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt | textClipped | Prompt.KeepPlaying | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt | textClipped | label:This can't be undone. | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |

## History

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| History | contrast | label:Matches | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| History | contrast | label:Matches | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| History | contrast | label:October 18, 2026 | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |

## MatchDetail

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| MatchDetail | contrast | Rematch | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:October 18, 2026 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Doubles • Best of 1 • < 1 min | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team B | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:0 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:1 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:2 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:3 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:4 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:5 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:6 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:7 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:8 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:9 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:10 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:11 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | contrast | label:Team A scored | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| MatchDetail | dynamicType | label:11 | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| MatchDetail | dynamicType | label:0 | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| MatchDetail | dynamicType | Rematch | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |

## Settings

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| Settings | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Settings | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Settings | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Settings | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Settings | contrast | (no element) | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Settings | textClipped | (no element) | Text clipped | Text of this element may be clipped at larger Dynamic Type sizes. |
| Settings | textClipped | label:Haptics | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |

## ManagePlayers

Empty state only: no saved players existed, so no rows were audited (see ManagePlayersWithRows).

## ManagePlayersWithRows

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| ManagePlayersWithRows | hitRegion | Me.Alice | Hit area is too small | The size of this SwiftUI.AccessibilityNode is too small for user to interact. |
| ManagePlayersWithRows | hitRegion | chevron.right | Hit area is too small | The size of this SwiftUI.AccessibilityNode is too small for user to interact. |
| ManagePlayersWithRows | hitRegion | chevron.right | Hit area is too small | The size of this SwiftUI.AccessibilityNode is too small for user to interact. |
| ManagePlayersWithRows | contrast | PhotoPicker.Alice | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| ManagePlayersWithRows | contrast | Rename.Alice | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| ManagePlayersWithRows | contrast | Me.Alice | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| ManagePlayersWithRows | contrast | PhotoPicker.Bob | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| ManagePlayersWithRows | contrast | Rename.Bob | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| ManagePlayersWithRows | contrast | SetMe.Bob | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| ManagePlayersWithRows | dynamicType | PhotoPicker.Bob | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| ManagePlayersWithRows | dynamicType | PhotoPicker.Alice | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| ManagePlayersWithRows | dynamicType | Me.Alice | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |

## HowToPlay

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| HowToPlay | contrast | label:A quick reference for pickleball's core rules — serving, scoring, and the two rules that trip up most beginners. | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| HowToPlay | contrast | label:All lines are in — including the serve's sideline, centerline, and baseline. The one exception is the kitchen line, which is out on a serve. | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| HowToPlay | contrast | label:A serve that clips the net but still lands in the correct box is live play, not a replay — that changed in 2021. | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| HowToPlay | contrast | label:The Two-Bounce Rule | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| HowToPlay | contrast | label:After the serve, the receiving side must let the ball bounce before returning it — and the serving side must let that return bounce too. Only after both of those bounces can either side start volleying (hitting the ball out of the air). This is what stops a team from serving and immediately rushing the net to end the point. | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |

## Paywall

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| Paywall | contrast | Not Now | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Paywall | contrast | label:The free version lets you play 1 full match, start to finish. Unlock Server Two Pro for a one-time $1.99 to play unlimited matches, forever. | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Paywall | contrast | Unlock Pro — $1.99 | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Paywall | contrast | label:Restore Purchases | Contrast nearly passed | Contrast is not high enough for SwiftUI.AccessibilityNode unless font size is larger. |
| Paywall | dynamicType | Not Now | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Paywall | textClipped | label:The free version lets you play 1 full match, start to finish. Unlock Server Two Pro for a one-time $1.99 to play unlimited matches, forever. | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Paywall | textClipped | label:You've Reached the Free Demo Limit | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Paywall | textClipped | Unlock Pro — $1.99 | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |

## Scoring@AXXL

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| Scoring@AXXL | contrast | Cancel Match | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring@AXXL | contrast | label:Tap to Score | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring@AXXL | contrast | label:SERVING | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring@AXXL | contrast | label:Tap to Score | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring@AXXL | contrast | label:Timeout (2) | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring@AXXL | contrast | label:Timeout (2) | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| Scoring@AXXL | dynamicType | label:0 | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring@AXXL | dynamicType | label:0 | Dynamic Type font sizes are unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring@AXXL | dynamicType | label:Tap to Score | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring@AXXL | dynamicType | label:Tap to Score | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring@AXXL | dynamicType | Cancel Match | Dynamic Type font sizes are partially unsupported | User will not be able to change the font size of this SwiftUI.AccessibilityNode |
| Scoring@AXXL | textClipped | label:Team A vs Team B | Text clipped | Text of this UILabel may be clipped at larger Dynamic Type sizes. |
| Scoring@AXXL | textClipped | label:SERVING | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring@AXXL | textClipped | label:Timeout (2) | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring@AXXL | textClipped | label:Tap to Score | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring@AXXL | textClipped | label:Tap to Score | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| Scoring@AXXL | textClipped | label:Timeout (2) | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |

## CancelMatchPrompt@AXXL

| Screen | Audit type | Element | Description | Detailed description |
|---|---|---|---|---|
| CancelMatchPrompt@AXXL | contrast | label:Current game 0 – 0 | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CancelMatchPrompt@AXXL | contrast | label:This can't be undone. | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CancelMatchPrompt@AXXL | contrast | Confirm Cancel Match | Contrast failed | Contrast failed for SwiftUI.AccessibilityNode |
| CancelMatchPrompt@AXXL | textClipped | Prompt.KeepPlaying | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt@AXXL | textClipped | label:Cancel this match? | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt@AXXL | textClipped | label:This can't be undone. | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt@AXXL | textClipped | label:Team A vs Team B | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt@AXXL | textClipped | Confirm Cancel Match | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |
| CancelMatchPrompt@AXXL | textClipped | label:Current game 0 – 0 | Text clipped | Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes. |

## Observations

These are judgements from reading the log only; nothing was visually verified on a device yet. Verify each before fixing.

**Coverage and stability of this baseline**
- Home is audited three ways: `Home` (empty state, "Play your first match to see it here."), `HomeWithMatch` (one finished match in history: Last Match card, quick-start row, matches-played card, Home unlock banner) and `HomeWithMatchAndMe` (players "Alice" and "Bob" saved, Alice set as Me: adds the Your Record card, W/L badges, `WinStreak`, `RecentForm`). Manage Players is audited as `ManagePlayers` (empty state only, no saved players, so 0 issues means nothing was audited) and `ManagePlayersWithRows` (two saved players, one marked Me).
- Every audit now waits for a hittable anchor element and a 0.5 s settle. Two consecutive full runs gave identical per-screen counts for every screen except two: `HomeWithMatchAndMe` 13 vs 14 and `ManagePlayersWithRows` 11 vs 12. The difference is the player-avatar initial/photo-picker contrast ("Contrast failed" for one avatar in one run, "Contrast nearly passed" for both avatars in the other; rows `label:A`, `label:B`, `PhotoPicker.Alice`, `PhotoPicker.Bob`). That points at avatar colours that differ between runs, so avatar contrast depends on the colour assigned to the player. Treat counts on those two screens as +/- 1. The earlier run-to-run wobble on `CancelMatchPrompt@AXXL` is gone (9 in both runs).
- The accessibility-size launch argument was verified to take effect: the coin-flip subtitle `FirstServeResult` is 18.0 pt tall at the default size and 50.3 pt (2.8x) tall at AccessibilityXXL; the test now requires at least 1.5x.

**Likely real**
- `dynamicType` "unsupported" / "partially unsupported": score digits `label:0` / `label:11` (Scoring, MatchDetail), `label:Tap to Score`, `Cancel Match`, `Cancel Coin Flip`, `Done`, `Not Now`, `Rematch`, and on the new screens the avatar initials (`label:A`, `label:B`, `PhotoPicker.<name>`), player names on the Home Last Match card (`label:Alice`, `label:Bob`), `label:W`, and `Me.<name>`. These use fixed-size fonts and fit the accessibility-size work planned in later tasks.
- `hitRegion` "Hit area is too small": MatchSetup `Log Final Score Instead` (plus two issues with no element), and on ManagePlayersWithRows `Me.Alice` and two `chevron.right` elements. Real against the 44 x 44 pt rule.
- `contrast` "failed" on controls on the accent colour or other filled backgrounds: `Start Match`, `New Match`, `Done`, `Get Started`, `Cancel Match` (toolbar), `Not Now`, `Prompt.KeepPlaying`, `Confirm Cancel Match`, and on the new screens `WinStreak`, `RecentForm`, `label:W`, `Rename.<name>`, `SetMe.<name>`, `Me.Alice`. Likely real, since white or coloured text on the accent colour is a known borderline pairing. `Prompt.KeepPlaying` contrast appears only at the default size (it is the one contrast row missing from `CancelMatchPrompt@AXXL`).

**textClipped is not size-sensitive**
Every `textClipped` issue has the detailed description "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes." The audit raises it at the default size (CoinFlip, Scoring, CancelMatchPrompt, Settings, Paywall) and again for the same elements at AccessibilityXXL (Scoring@AXXL, CancelMatchPrompt@AXXL), so it is a static heuristic about the element, not a measured clip at the current size. Do not treat an AXXL `textClipped` as proof of real clipping, and do not treat the default-size ones as false positives either: each needs an on-device look at a large size (screenshots at AccessibilityXXL) before deciding.

**Likely false positives or needing verification**
- MatchDetail contrast: 31 issues, almost all "Contrast failed", including every point-by-point row (`Team A scored`, the running score digits). The uniformity suggests the audit samples a background (a material or gradient behind the list) incorrectly. Verify visually before changing colours.
- All "Contrast nearly passed" items (secondary-label text on Home, HomeWithMatch, History, Settings, MatchSetup, Onboarding, Paywall; the five `(no element)` rows on Settings and the seven on MatchSetup): borderline, often `.secondary` text over grouped-list backgrounds. Low priority.
- `elementDetection` "Potentially inaccessible text" with no element on the Cancel Match prompt: reported at the default size only (`CancelMatchPrompt` has 11 issues, `CancelMatchPrompt@AXXL` 9; the two missing at AXXL are this `elementDetection` issue and the `Prompt.KeepPlaying` contrast issue). Cannot be attributed to a view from the log; check whether the prompt has text rendered outside an accessibility element.
- `Settings` `(no element)` `textClipped`: no element reported, so it cannot be located from the log alone.
