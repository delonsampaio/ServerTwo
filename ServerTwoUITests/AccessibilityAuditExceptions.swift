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
// type, wording). `AccessibilityAuditUITests` prints the unused capacity of
// every audited screen (`A11Y-AUDIT-UNUSED|...`) so a stale entry shows up in
// the log.
//
// Two kinds of entries: (a) heuristic rows that were reviewed (looked at with
// short fixture names at AX4; not proven, see each reason) or are system
// behaviour, and (b) the contrast items that remain after the colours were
// made accessible natively (named colours in `Assets.xcassets`, see
// `AppColors.swift`): each says what it is and what was measured. Nothing here
// is a whole-category or whole-screen wildcard.

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
    /// Why this issue is accepted, and what was measured.
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
        hitArea +
        dyn +
        c_toolbar +
        c_glass +
        c_bordered +
        c_pill +
        c_tabbar +
        c_players

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
            // Same static heuristic, on the long inline navigation title of a
            // named doubles match (the only text it reports there).
            screen: "ScoringWithPartnerPositions", auditType: "textClipped", elements: ["label:Delon & Katie vs Fred & Gina"],
            descriptionContains: "Text clipped", reason: clippedReason
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

    // MARK: Hit area

    private static let hitAreaReason = "the \"Me\" status badge on a Manage Players row is a non-interactive Text (no gesture, not a control); the audit's hit-area heuristic measures its small accessibility node. Giving it a 44 pt accessibility frame only made it cover the player name above it for VoiceOver touch exploration, so it was left small on purpose. The controls on that row (Rename, Set as Me, photo) are all 44 pt."

    private static let hitArea: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "ManagePlayersWithRows", auditType: "hitRegion", elements: ["(no element)", "Me.Alice"],
            descriptionContains: "Hit area is too small", reason: hitAreaReason
        ),
    ]

    // MARK: Dynamic Type "partially unsupported" (reviewed, reasons per element)

    private static let dynHistoryReason = "reviewed: the History stats card number (\"1\") and its \"Matches\" caption; they scale visibly at AX4 in the History screenshot and nothing is clipped (looked at once in simulator screenshots with short fixture names (Alice, Bob, Team A, Team B) at the default size and at AX4 only; long names and AX5 are on the device-check list)"

    private static let dynMatchDetailReason = "reviewed: score digits are scaled with a deliberate maximum of 52 pt so two digits never wrap (capped by design, so the audit sees them as only partly scaling), plus the system toolbar \"Rematch\" text which has no API to scale it; looked at at AX4 with short names: intact"

    private static let dynOnboardingReason = "reviewed: \"Done\" is the system toolbar button text, which has no API to scale it further; looked at at AX4: intact"

    private static let dynPlayersReason = "reviewed: Manage Players row text. The audit reports it in some runs and not in others (it was dropped once because it did not fire in one run, then fired in the next full run), so it stays listed: Alice, the \"Me\" badge and a long name (\"Bartholomew Featherstonehaugh\") were looked at at AX4: they scale and wrap, nothing is truncated (the long name breaks mid-word across 5 lines at AX4 because the row is narrow; wrapping is not truncation, judged acceptable, listed for the device checks)"

    private static let dynPartnerReason = "reviewed, by design: the same Scoring items (see dynScoringReason), plus the partner rows of a named doubles card: the names (headline) and the R/L badges scale with Dynamic Type but the block is deliberately capped at accessibility2 so two rows plus the digits still fit a half-width card, which is what the audit reports as partially unsupported. Looked at at AX4 with short names (Delon, Katie, Fred, Gina): nothing clipped (long names and AX5 are on the device-check list)"

    private static let dynScoringReason = "reviewed, by design: score digits are scaled up to a 128 pt maximum and shrink to fit rather than wrap; the \"SERVER 2\" badge (\"SERVER 1\" / \"SERVING\" in other modes) is deliberately capped at accessibility1 so it does not truncate; \"Tap to Score\" and \"Tap for Side Out\" (\"Tap for 2nd Server\" with server 1) are caption2 hints that wrap to two lines at AX sizes; \"Cancel Match\" is system toolbar text. Looked at at AX4 with short names: nothing clipped (long names and AX5 are on the device-check list)"

    private static let dynSettingsReason = "static dynamicType heuristic on the Haptics row, whose code did not change; it first appeared once the Server Two Pro section was added above it. Looked at in a dark-mode simulator screenshot at AX4 (UICTContentSizeCategoryAccessibilityXXL): the Haptics label (and Voice Announcer, same kind of row) is rendered at the large size, wraps and is not clipped, so the text does scale. The Settings textClipped entry for \"(no element)\" / label:Haptics (shared with the same row) is in `clipped` above. Reviewed at that size only, on one screenshot; not proven at AX5"

    private static let dyn: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "Settings", auditType: "dynamicType", elements: ["label:Haptics"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", reason: dynSettingsReason
        ),
        KnownFalsePositive(
            screen: "History", auditType: "dynamicType", elements: ["label:1", "label:Matches"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 2, reason: dynHistoryReason
        ),
        KnownFalsePositive(
            screen: "MatchDetail", auditType: "dynamicType", elements: ["Rematch", "label:0", "label:11"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 3, reason: dynMatchDetailReason
        ),
        KnownFalsePositive(
            screen: "ManagePlayersWithRows", auditType: "dynamicType", elements: ["Me.Alice", "PlayerRow.Alice", "PlayerRow.Bob"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 3, reason: dynPlayersReason
        ),
        KnownFalsePositive(
            screen: "Onboarding", auditType: "dynamicType", elements: ["Done"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", reason: dynOnboardingReason
        ),
        KnownFalsePositive(
            screen: "Scoring", auditType: "dynamicType", elements: ["Cancel Match", "label:0", "label:SERVER 2", "label:Tap for Side Out", "label:Tap to Score"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 6, reason: dynScoringReason
        ),
        KnownFalsePositive(
            screen: "ScoringWithPartnerPositions", auditType: "dynamicType",
            elements: ["Cancel Match", "label:0", "label:SERVER 2", "label:Tap for Side Out", "label:Tap to Score", "label:Delon", "label:Fred", "label:Gina", "label:Katie", "label:L", "label:R"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 14, reason: dynPartnerReason
        ),
        KnownFalsePositive(
            screen: "Scoring@AXXL", auditType: "dynamicType", elements: ["Cancel Match", "label:0", "label:SERVER 2", "label:Tap for Side Out", "label:Tap to Score"],
            descriptionContains: "Dynamic Type font sizes are partially unsupported", maxOccurrences: 6, reason: dynScoringReason
        ),
    ]

    // MARK: Contrast: what the new colours do not clear in the audit

    private static let c_toolbarReason = "system toolbar button on Liquid Glass (no API to style the glass). The label is tinted with the text-tuned `accentText` (dark #85BEFF) or `errorRed` (dark #FF7A72); measured on a simulator screenshot against the rendered glass (#202020) the text is 7.2:1 (accent text) and 6.4:1 (Cancel Match), well over 4.5:1, yet the audit rates it failed: it cannot read the glass background. Not proven beyond that one dark-mode screenshot"

    private static let c_toolbar: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "CoinFlip", auditType: "contrast", elements: ["(no element)", "Cancel Coin Flip"],
            descriptionContains: "Contrast failed", reason: c_toolbarReason
        ),
        KnownFalsePositive(
            screen: "MatchDetail", auditType: "contrast", elements: ["Rematch"],
            descriptionContains: "Contrast failed", reason: c_toolbarReason
        ),
        KnownFalsePositive(
            screen: "Onboarding", auditType: "contrast", elements: ["Done"],
            descriptionContains: "Contrast failed", reason: c_toolbarReason
        ),
        KnownFalsePositive(
            screen: "Paywall", auditType: "contrast", elements: ["(no element)", "Not Now"],
            descriptionContains: "Contrast failed", reason: c_toolbarReason
        ),
        KnownFalsePositive(
            screen: "Scoring", auditType: "contrast", elements: ["Cancel Match"],
            descriptionContains: "Contrast failed", reason: c_toolbarReason
        ),
        KnownFalsePositive(
            screen: "ScoringWithPartnerPositions", auditType: "contrast", elements: ["Cancel Match"],
            descriptionContains: "Contrast failed", reason: c_toolbarReason
        ),
        KnownFalsePositive(
            screen: "Scoring@AXXL", auditType: "contrast", elements: ["Cancel Match"],
            descriptionContains: "Contrast failed", reason: c_toolbarReason
        ),
    ]

    // MARK: Contrast: glass buttons in sheets

    private static let c_glassReason = "Liquid Glass button inside a sheet: white label on the accent (dark #2D6BF9, white 4.58:1; measured 4.58:1 on the Flip Coin button of a dark screenshot, the same fill) or `errorRed` text on red-tinted glass. The same accent passes on Home's glass New Match button; the sheet material behind the glass is what the audit rates here. The rendered sheet button was not measured. A darker accent (#2563EB) was tried and the audit rated these worse"

    private static let c_glass: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "CancelMatchPrompt", auditType: "contrast", elements: ["(no element)", "Prompt.KeepPlaying"],
            descriptionContains: "Contrast nearly passed", reason: c_glassReason
        ),
        KnownFalsePositive(
            screen: "CancelMatchPrompt", auditType: "contrast", elements: ["(no element)", "Confirm Cancel Match"],
            descriptionContains: "Contrast failed", reason: c_glassReason
        ),
        KnownFalsePositive(
            screen: "CancelMatchPrompt@AXXL", auditType: "contrast", elements: ["(no element)", "Confirm Cancel Match"],
            descriptionContains: "Contrast failed", reason: c_glassReason
        ),
        KnownFalsePositive(
            screen: "Onboarding", auditType: "contrast", elements: ["Get Started"],
            descriptionContains: "Contrast nearly passed", reason: c_glassReason
        ),
    ]

    // MARK: Contrast: bordered "Won Spin" buttons

    private static let c_borderedReason = "bordered button, `.primary` label on a blue wash (`accentText` tint): measured on a dark screenshot the label is white (#F7F7F8) on #273544, 11.7:1, yet the audit rates it failed (it appears to compare the label with the tint colour, not with the wash it is drawn on)"

    private static let c_bordered: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "CoinFlip", auditType: "contrast", elements: ["Team A Won Spin", "Team B Won Spin"],
            descriptionContains: "Contrast failed", maxOccurrences: 2, reason: c_borderedReason
        ),
    ]

    // MARK: Contrast: Rematch pill on the Home Last Match card

    private static let c_pillReason = "accent text on the grey pill fill (`PillButtonStyle`): measured on a dark screenshot `accentText` #85BEFF on the pill fill #3B3B3E is 5.74:1 (4.94:1 with the earlier #6CB0FF, also rated failed); the same pill style passes on Manage Players rows, only this one on the Last Match card is rated failed"

    private static let c_pill: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "HomeWithMatch", auditType: "contrast", elements: ["Rematch"],
            descriptionContains: "Contrast failed", reason: c_pillReason
        ),
        KnownFalsePositive(
            screen: "HomeWithMatchAndMe", auditType: "contrast", elements: ["Rematch"],
            descriptionContains: "Contrast failed", reason: c_pillReason
        ),
    ]

    // MARK: Contrast: rows under the translucent tab bar, and unexplained text rows

    private static let c_tabbarReason = "reviewed, not proven: the row sits half behind the translucent tab bar in the audited (unscrolled) view; the audit reads the blurred bar as the background. Match Detail's \"11\" and \"11-0\" are the 11th point row; \"1\" was not identified, it may be a part of the same row"

    private static let c_howtoReason = "unexplained: these two secondary paragraphs are fully visible (not behind the tab bar) in the audited view, and measured on a dark screenshot `secondaryText` #AEAEB4 on the thin-material card (#1F1F1F) is 7.47:1 (the card's `.primary` text, 15.25:1, passes), yet the audit rates them failed. Not understood; kept so the screen is still audited"

    private static let c_tabbar: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "HowToPlay", auditType: "contrast",
            elements: [
                "label:After the serve, the receiving side must let the ball bounce before returning it — and the serving side must let that return bounce too. Only after both of those bounces can either side start volleying (hitting the ball out of the air). This is what stops a team from serving and immediately rushing the net to end the point.",
                "label:The Two-Bounce Rule",
            ],
            descriptionContains: "Contrast failed", maxOccurrences: 2,
            reason: "reviewed, not proven: the card (heading and first paragraph) sits half behind the translucent tab bar in the audited (unscrolled) view and the audit reads the blurred bar as the background; both are `.primary` text"
        ),
        KnownFalsePositive(
            screen: "HowToPlay", auditType: "contrast",
            elements: [
                "label:A serve that clips the net but still lands in the correct box is live play, not a replay — that changed in 2021.",
                "label:All lines are in — including the serve's sideline, centerline, and baseline. The one exception is the kitchen line, which is out on a serve.",
            ],
            descriptionContains: "Contrast failed", maxOccurrences: 2, reason: c_howtoReason
        ),
        KnownFalsePositive(
            screen: "MatchDetail", auditType: "contrast", elements: ["label:1", "label:11", "label:11-0"],
            descriptionContains: "Contrast failed", maxOccurrences: 3, reason: c_tabbarReason
        ),
    ]

    // MARK: Contrast: Manage Players row

    private static let c_playersReason = "reported on the Alice row text in some runs and not in others (the avatar colour is random per run). Measured on a dark screenshot: initials white on the avatar fill 5.5 to 6.9:1, Me badge 6.75:1, Rename / Set as Me pills 5.09:1. Which element it is was not identified"

    private static let c_players: [KnownFalsePositive] = [
        KnownFalsePositive(
            screen: "ManagePlayersWithRows", auditType: "contrast", elements: ["PlayerRow.Alice"],
            descriptionContains: "Contrast failed", reason: c_playersReason
        ),
        KnownFalsePositive(
            screen: "ManagePlayersWithRows", auditType: "elementDetection", elements: ["(no element)"],
            descriptionContains: "Potentially inaccessible text", maxOccurrences: 2,
            reason: "the white initials (\"A\", \"B\") inside the two avatar buttons. The button is labelled \"Change photo for <name>\" and the initial is decorative, but the darker palette made the initials legible enough for the audit's text recognition, which now finds them (they were not detected at 2.1 to 4:1). Making the initial a separate accessibility element would make VoiceOver read a stray letter"
        ),
    ]
}
