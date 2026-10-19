// Documented exceptions for `AccessibilityAuditUITests` (strict mode).
//
// An issue is ignored only when it matches ALL of an entry's screen, audit
// type, one of its elements and its description substring, and only up to
// `maxOccurrences` issues per audit of that screen (the count is shared by the
// entry's elements). The audit does not report the same element name on every
// run: the same issue is attributed to an element in one run and to
// "(no element)" in another, and its detailed description is generic, so each
// entry lists every element name it has been seen under (plus "(no element)")
// and is limited by the occurrence count. A new issue on a different element
// fails, and so does an extra unattributed one.
//
// Each cap is the largest count actually observed for its (screen, audit
// type, wording) in all recorded runs (strict runs 2 to 19 and the full-suite
// runs). Only the two avatar screens (HomeWithMatchAndMe, ManagePlayersWithRows)
// get +1 on their contrast entries, because the per-run avatar colour moves
// rows between "failed" and "nearly passed". `AccessibilityAuditUITests` prints
// the unused capacity of every audited screen (`A11Y-AUDIT-UNUSED|...`) so a
// stale entry shows up in the log.
//
// Two kinds of entries: (a) heuristic rows that were reviewed (looked at with
// short fixture names at AX4; not proven, see each reason) or are system
// behaviour, and (b) contrast items whose reason starts
// "design decision pending": they need a new or darker colour that has not
// been chosen yet. Nothing here is a whole-category or whole-screen wildcard.

/// One audit issue that is understood and accepted.
struct KnownFalsePositive {
    let screen: String
    let auditType: String
    /// Element identifiers or "label:<text>" names the issue has been
    /// reported under, including "(no element)" when the audit cannot attribute it.
    let elements: [String]
    /// Substring of the issue's compact description (for example
    /// "Contrast failed"), so a different problem on the same element is not
    /// hidden by an entry for another one.
    let descriptionContains: String
    /// How many times this issue may be reported in one audit of the screen.
    let maxOccurrences: Int
    /// Why this issue is accepted (or, for contrast items, "design decision
    /// pending: ...").
    let reason: String

    init(
        screen: String, auditType: String, elements: [String], descriptionContains: String,
        maxOccurrences: Int = 1, reason: String
    ) {
        // An empty substring matches every description: it would act as a
        // wildcard for the whole element, which is never intended.
        precondition(!descriptionContains.isEmpty, "descriptionContains must not be empty")
        precondition(!elements.isEmpty, "elements must not be empty")
        precondition(maxOccurrences >= 1, "maxOccurrences must be at least 1")
        self.screen = screen
        self.auditType = auditType
        self.elements = elements
        self.descriptionContains = descriptionContains
        self.maxOccurrences = maxOccurrences
        self.reason = reason
    }
}

enum AccessibilityAuditExceptions {
    static let all: [KnownFalsePositive] =
        clipped +
        behindsheet +
        dyn +
        c_accent +
        c_mixed +
        c_secondary +
        c_howto +
        c_homeme +
        c_avatar +
        c_sequence +
        c_sheets

    // MARK: Text clipped (static heuristic, reviewed with short names at AX4)

    private static let clippedReason = "static textClipped heuristic, reported identically at default size and at AX4 (it cannot see the real layout); reviewed, not proven: looked at once in simulator screenshots with short fixture names (Alice, Bob, Team A, Team B) at the default size and at AX4 only; long names and AX5 are on the device-check list. Nothing was visibly clipped on Scoring, the Cancel Match prompt, Settings and Manage Players."

    private static let clipped: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "CancelMatchPrompt", auditType: "textClipped", elements: ["(no element)"],
            descriptionContains: "Text clipped", maxOccurrences: 5, reason: clippedReason
        ),
        KnownFalsePositive(
            screen: "ManagePlayersWithRows", auditType: "textClipped", elements: ["(no element)", "PlayerRow.Alice"],
            descriptionContains: "Text clipped", reason: clippedReason
        ),
        KnownFalsePositive(
            screen: "Scoring", auditType: "textClipped", elements: ["label:Team A", "label:Team A vs Team B", "label:Team B", "label:Timeout (2)"],
            descriptionContains: "Text clipped", maxOccurrences: 4, reason: clippedReason
        ),
        KnownFalsePositive(
            screen: "Scoring@AXXL", auditType: "textClipped", elements: ["label:Team A", "label:Team A vs Team B", "label:Team B", "label:Timeout (2)"],
            descriptionContains: "Text clipped", maxOccurrences: 4, reason: clippedReason
        ),
        KnownFalsePositive(
            screen: "Settings", auditType: "textClipped", elements: ["(no element)", "label:Haptics"],
            descriptionContains: "Text clipped", maxOccurrences: 2, reason: clippedReason
        ),
    ]

    // MARK: Potentially inaccessible text

    private static let behindsheetReason = "text of the scoring screen visible behind the presented sheet (the system hides the background from accessibility; the same row appears for the Game Over sheet at default size); not the sheet content; the sheet badge was ruled out by removing its accessibilityHidden"

    private static let behindsheet: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "CancelMatchPrompt", auditType: "elementDetection", elements: ["(no element)"],
            descriptionContains: "Potentially inaccessible text", reason: behindsheetReason
        ),
    ]

    // MARK: Dynamic Type "partially unsupported" (reviewed, reasons per element)

    private static let dynHistoryReason = "reviewed: the History stats card number (\"1\") and its \"Matches\" caption; they scale visibly at AX4 in the History screenshot and nothing is clipped (looked at once in simulator screenshots with short fixture names (Alice, Bob, Team A, Team B) at the default size and at AX4 only; long names and AX5 are on the device-check list)"

    private static let dynPlayersReason = "reviewed: Manage Players row text. After the Manage Players title fix, Alice, the \"Me\" badge and a long name (\"Bartholomew Featherstonehaugh\") were looked at at AX4: they scale and wrap, nothing is truncated (the long name breaks mid-word across 5 lines at AX4 because the row is narrow; wrapping is not truncation, judged acceptable, listed for the device checks)"

    private static let dynMatchDetailReason = "reviewed: score digits are scaled with a deliberate maximum of 52 pt so two digits never wrap (capped by design, so the audit sees them as only partly scaling), plus the system toolbar \"Rematch\" text which has no API to scale it; looked at at AX4 with short names: intact"

    private static let dynOnboardingReason = "reviewed: \"Done\" is the system toolbar button text, which has no API to scale it further; looked at at AX4: intact"

    private static let dynScoringReason = "reviewed, by design: score digits are scaled up to a 128 pt maximum and shrink to fit rather than wrap; the \"SERVING\" badge is deliberately capped at accessibility1 so it does not truncate; \"Tap to Score\" is a caption2 hint that wraps to two lines at AX sizes; \"Cancel Match\" is system toolbar text. Looked at at AX4 with short names: nothing clipped (long names and AX5 are on the device-check list)"

    private static let dyn: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "History", auditType: "dynamicType", elements: ["label:1", "label:Matches"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 2, reason: dynHistoryReason
        ),
        KnownFalsePositive(
            screen: "ManagePlayersWithRows", auditType: "dynamicType", elements: ["Me.Alice", "PlayerRow.Alice", "PlayerRow.Bob"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 3, reason: dynPlayersReason
        ),
        KnownFalsePositive(
            screen: "MatchDetail", auditType: "dynamicType", elements: ["Rematch", "label:0", "label:11"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 3, reason: dynMatchDetailReason
        ),
        KnownFalsePositive(
            screen: "Onboarding", auditType: "dynamicType", elements: ["Done"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", reason: dynOnboardingReason
        ),
        KnownFalsePositive(
            screen: "Scoring", auditType: "dynamicType", elements: ["Cancel Match", "label:0", "label:SERVING", "label:Tap to Score"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 6, reason: dynScoringReason
        ),
        KnownFalsePositive(
            screen: "Scoring@AXXL", auditType: "dynamicType", elements: ["Cancel Match", "label:0", "label:SERVING", "label:Tap to Score"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 6, reason: dynScoringReason
        ),
    ]

    // MARK: design decision pending: accent blue and system toolbar buttons

    private static let c_accentReason = "design decision pending: accent blue #007AFF as text or white on accent 4.02:1 (needs 4.5:1) on buttons, badges and system toolbar buttons (Done, Not Now, Cancel Match, Cancel Coin Flip; no styling hook); unattributed rows are the accent-filled controls and red/orange tints of that screen"

    private static let c_accent: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "CancelMatchPrompt", auditType: "contrast", elements: ["(no element)", "Confirm Cancel Match", "Prompt.KeepPlaying"],
            descriptionContains: "Contrast failed", maxOccurrences: 2, reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "CancelMatchPrompt@AXXL", auditType: "contrast", elements: ["(no element)", "Confirm Cancel Match"],
            descriptionContains: "Contrast failed", reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "CoinFlip", auditType: "contrast", elements: ["(no element)", "Cancel Coin Flip"],
            descriptionContains: "Contrast failed", reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "Home", auditType: "contrast", elements: ["label:New Match"],
            descriptionContains: "Contrast failed", reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "HomeWithMatch", auditType: "contrast", elements: ["Rematch", "label:New Match"],
            descriptionContains: "Contrast failed", maxOccurrences: 2, reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "MatchSetup", auditType: "contrast", elements: ["Start Match"],
            descriptionContains: "Contrast failed", reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "Onboarding", auditType: "contrast", elements: ["Done", "Get Started"],
            descriptionContains: "Contrast failed", maxOccurrences: 2, reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "Paywall", auditType: "contrast", elements: ["(no element)", "Not Now"],
            descriptionContains: "Contrast failed", reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "Scoring", auditType: "contrast", elements: ["Cancel Match", "label:SERVING", "label:Timeout (2)"],
            descriptionContains: "Contrast failed", maxOccurrences: 4, reason: c_accentReason
        ),
        KnownFalsePositive(
            screen: "Scoring@AXXL", auditType: "contrast", elements: ["Cancel Match", "label:SERVING", "label:Timeout (2)"],
            descriptionContains: "Contrast failed", maxOccurrences: 4, reason: c_accentReason
        ),
    ]

    // MARK: design decision pending: accent blue and secondary captions

    private static let c_mixedReason = "design decision pending: accent blue 4.02:1 (Flip Coin, Unlock buttons, pills) and `.secondary` captions roughly 3.4 to 4.4:1 (needs 4.5:1)"

    private static let c_mixed: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "CoinFlip", auditType: "contrast", elements: ["(no element)", "FirstServeResult", "Flip Coin", "Team A Won Spin", "Team B Won Spin"],
            descriptionContains: "Contrast nearly passed", maxOccurrences: 4, reason: c_mixedReason
        ),
        KnownFalsePositive(
            screen: "HomeWithMatch", auditType: "contrast", elements: ["label:Unlock Server Two Pro — $1.99"],
            descriptionContains: "Contrast nearly passed", reason: c_mixedReason
        ),
        KnownFalsePositive(
            screen: "Paywall", auditType: "contrast", elements: ["(no element)", "Unlock Pro — $1.99", "label:Restore Purchases", "label:The free version lets you play 1 full match, start to finish. Unlock Server Two Pro for a one-time $1.99 to play unlimited matches, forever."],
            descriptionContains: "Contrast nearly passed", maxOccurrences: 3, reason: c_mixedReason
        ),
    ]

    // MARK: design decision pending: secondary captions

    private static let c_secondaryReason = "design decision pending: `.secondary` / `.tertiary` caption text on grouped or material backgrounds, roughly 3.4 to 4.4:1 (needs 4.5:1); passing means `.primary` everywhere, a visible hierarchy change"

    private static let c_secondary: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "History", auditType: "contrast", elements: ["(no element)", "label:Matches", "label:<date>"],
            descriptionContains: "Contrast nearly passed", maxOccurrences: 3, reason: c_secondaryReason
        ),
        KnownFalsePositive(
            screen: "Home", auditType: "contrast", elements: ["label:Play your first match to see it here."],
            descriptionContains: "Contrast nearly passed", reason: c_secondaryReason
        ),
        KnownFalsePositive(
            screen: "MatchSetup", auditType: "contrast", elements: ["(no element)", "Log Final Score Instead", "label:Match Rules", "label:Mode", "label:Swap Partners", "label:Swap Teams", "label:Team A", "label:Team B"],
            descriptionContains: "Contrast nearly passed", maxOccurrences: 7, reason: c_secondaryReason
        ),
        KnownFalsePositive(
            screen: "Onboarding", auditType: "contrast", elements: ["label:Always know which partner belongs on the left or right court.", "label:Score singles and doubles matches point by point. Server Two keeps track of who's serving, which side everyone's on, and your stats over time.", "label:See your record with every partner and against every rival.", "label:Set this once so your personal win/loss record starts tracking automatically.", "label:Tap a card to score a point, or press and hold to fix a disputed score."],
            descriptionContains: "Contrast nearly passed", maxOccurrences: 5, reason: c_secondaryReason
        ),
        KnownFalsePositive(
            screen: "Scoring", auditType: "contrast", elements: ["label:Tap to Score"],
            descriptionContains: "Contrast nearly passed", maxOccurrences: 2, reason: c_secondaryReason
        ),
        KnownFalsePositive(
            screen: "Settings", auditType: "contrast", elements: ["(no element)", "label:1.0", "label:Appearance", "label:Audio & Haptics", "label:Help", "label:Players"],
            descriptionContains: "Contrast nearly passed", maxOccurrences: 5, reason: c_secondaryReason
        ),
    ]

    // MARK: design decision pending: How to Play text

    private static let c_howtoReason = "design decision pending: How to Play body and heading text is `.secondary` on the grouped background, roughly 3.4 to 4.4:1 (the audit rates it failed or nearly passed)"

    private static let c_howto: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "HowToPlay", auditType: "contrast", elements: ["label:A serve that clips the net but still lands in the correct box is live play, not a replay — that changed in 2021.", "label:After the serve, the receiving side must let the ball bounce before returning it — and the serving side must let that return bounce too. Only after both of those bounces can either side start volleying (hitting the ball out of the air). This is what stops a team from serving and immediately rushing the net to end the point.", "label:All lines are in — including the serve's sideline, centerline, and baseline. The one exception is the kitchen line, which is out on a serve.", "label:The Two-Bounce Rule"],
            descriptionContains: "Contrast failed", maxOccurrences: 4, reason: c_howtoReason
        ),
        KnownFalsePositive(
            screen: "HowToPlay", auditType: "contrast", elements: ["label:A quick reference for pickleball's core rules — serving, scoring, and the two rules that trip up most beginners."],
            descriptionContains: "Contrast nearly passed", reason: c_howtoReason
        ),
    ]

    // MARK: design decision pending: Home with a Me player

    private static let c_homemeReason = "design decision pending: accent blue 4.02:1 (New Match, Rematch, Unlock banner), white on green #34C759 2.22:1 and green or red text on a 20% tint (W badge, recent form, win streak), avatar palette (per-run colour, see below); wording and count vary per run"

    private static let c_homeme: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "HomeWithMatchAndMe", auditType: "contrast", elements: ["(no element)", "PhotoPicker.Alice", "PhotoPicker.Bob", "Rematch", "label:A", "label:B", "label:New Match", "label:W"],
            descriptionContains: "Contrast failed", maxOccurrences: 6, reason: c_homemeReason
        ),
        KnownFalsePositive(
            screen: "HomeWithMatchAndMe", auditType: "contrast", elements: ["(no element)", "PhotoPicker.Alice", "PhotoPicker.Bob", "label:A", "label:B", "label:Unlock Server Two Pro — $1.99"],
            descriptionContains: "Contrast nearly passed", maxOccurrences: 4, reason: c_homemeReason
        ),
    ]

    // MARK: design decision pending: avatar palette, Me badge and pills

    private static let c_avatarReason = "design decision pending: avatar initials are white on a per-player palette colour (teal 2.57, orange 2.20, mint 2.12, brown 3.50, pink 3.65, blue 4.02, purple 4.13:1), the Me badge is accent text on a light accent tint and the Rename / Set as Me pills are accent on grey; the colour differs per run, so wording and count vary"

    private static let c_avatar: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "ManagePlayersWithRows", auditType: "contrast", elements: ["(no element)", "Me.Alice", "PhotoPicker.Alice", "PhotoPicker.Bob", "label:A", "label:B"],
            descriptionContains: "Contrast failed", maxOccurrences: 2, reason: c_avatarReason
        ),
        KnownFalsePositive(
            screen: "ManagePlayersWithRows", auditType: "contrast", elements: ["(no element)", "PhotoPicker.Alice", "PhotoPicker.Bob", "label:A", "label:B"],
            descriptionContains: "Contrast nearly passed", reason: c_avatarReason
        ),
    ]

    // MARK: design decision pending: Match Detail sequence numbers and loser digit

    private static let c_sequenceReason = "design decision pending: point sequence numbers are `.tertiary` captions on thin material (passing needs `.primary`, which flattens the row hierarchy), the losing team digit is `.secondary` by design, and the toolbar Rematch button is accent blue 4.02:1 (system toolbar)"

    private static let c_sequence: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "MatchDetail", auditType: "contrast", elements: ["Rematch", "label:0", "label:1", "label:10", "label:11", "label:2", "label:3", "label:4", "label:5", "label:6", "label:7", "label:8", "label:9"],
            descriptionContains: "Contrast failed", maxOccurrences: 13, reason: c_sequenceReason
        ),
    ]

    // MARK: design decision pending: Game Over and Finish Match sheets at AX4

    private static let c_sheetsReason = "design decision pending: `.secondary` text on the sheet card (team name captions, losing score digit, \"Teams switch sides\", \"First serve\", \"Next game starts\" lines) fails at accessibility size 4, and the primary button is accent blue 4.02:1; the audit attributes these rows to an element in some runs and not in others"

    private static let c_sheets: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "FinishMatchSheet@AXXL", auditType: "contrast", elements: ["(no element)", "label:0", "label:Team A", "label:Team B"],
            descriptionContains: "Contrast failed", maxOccurrences: 3, reason: c_sheetsReason
        ),
        KnownFalsePositive(
            screen: "GameOverSheet@AXXL", auditType: "contrast", elements: ["(no element)", "label:0", "label:First serve: Team A.", "label:First serve: Team B.", "label:Next game starts at 0-0.", "label:Team A", "label:Team B", "label:Teams switch sides."],
            descriptionContains: "Contrast failed", maxOccurrences: 6, reason: c_sheetsReason
        ),
    ]
}
