import ActivityKit
import SwiftUI
import WidgetKit

/// Read-only match scoreboard for the Lock Screen, StandBy (the same
/// `.medium` presentation, scaled up by the system) and the Dynamic Island.
/// No buttons and no intents: scoring only happens in the app.
struct PickleballLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickleballActivityAttributes.self) { context in
            LockScreenScoreboard(attributes: context.attributes, state: context.state, isStale: context.isStale)
                // Tapping the scoreboard surfaces the live match, not whichever
                // tab the app was last left on (handled in RootTabView).
                .widgetURL(Self.playURL)
                // A dark, slightly see-through surface lets the system dim it
                // in Always-On / StandBy night mode instead of a hard-coded
                // opaque background inside the view. The tint is a fixed black
                // (not a named colour) because the white-on-dark text and the
                // dark-scheme accent below are all chosen for a dark surface
                // whatever the system appearance.
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedTeam(
                        name: context.attributes.teamAName,
                        score: context.state.teamAScore,
                        isServing: context.state.isTeamAServing && !context.state.isMatchOver
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTeam(
                        name: context.attributes.teamBName,
                        score: context.state.teamBScore,
                        isServing: !context.state.isTeamAServing && !context.state.isMatchOver
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedStatus(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                CompactScore(
                    initial: TeamMark.initial(forA: true, attributes: context.attributes),
                    score: context.state.teamAScore,
                    isServing: context.state.isTeamAServing && !context.state.isMatchOver,
                    markFirst: true,
                    label: Self.accessibilityLabel(
                        name: context.attributes.teamAName, score: context.state.teamAScore
                    )
                )
            } compactTrailing: {
                CompactScore(
                    initial: TeamMark.initial(forA: false, attributes: context.attributes),
                    score: context.state.teamBScore,
                    isServing: !context.state.isTeamAServing && !context.state.isMatchOver,
                    markFirst: false,
                    label: Self.accessibilityLabel(
                        name: context.attributes.teamBName, score: context.state.teamBScore
                    )
                )
            } minimal: {
                MinimalGlyph(state: context.state)
            }
            .widgetURL(Self.playURL)
            .keylineTint(Color.accentColor)
        }
    }

    static let playURL = URL(string: "servertwo://play")

    static func accessibilityLabel(name: String, score: Int) -> String {
        "\(name), \(score) \(score == 1 ? "point" : "points")"
    }
}

/// "SERVER 2" in doubles side-out scoring, plain "SERVING" otherwise: the same
/// wording as the in-app serving badge.
private func servingText(_ state: PickleballActivityAttributes.ContentState) -> String {
    state.serverNumber.map { "SERVER \($0)" } ?? "SERVING"
}

/// One-letter team marks for the compact presentation. When both teams start
/// with the same letter the marks fall back to A / B, so the two sides of the
/// camera cutout never look identical.
private enum TeamMark {
    static func initial(forA isTeamA: Bool, attributes: PickleballActivityAttributes) -> String {
        let a = letter(attributes.teamAName)
        let b = letter(attributes.teamBName)
        if a == b { return isTeamA ? "A" : "B" }
        return isTeamA ? a : b
    }

    private static func letter(_ name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}

// MARK: - Lock Screen / StandBy

/// A Lock Screen Live Activity may be at most 160 pt tall, and anything past it
/// is clipped, so this layout is built from two rows only and sized by metrics
/// (default text size, doubles side-out, Best of 3, SERVER n, games tally):
///
///     padding top/bottom      10 + 10 = 20
///     summary row (caption)   16  (12 pt font, 16 pt line); the games tally is
///                             inline in this row, never a row of its own
///     row spacing              4
///     name (subheadline)      20  (one line, shrinks instead of wrapping)
///     score (54 pt rounded)  ~48  (line box trimmed to 0.88x the font size)
///     serving line (caption2) 13  (reserved in BOTH columns, so the two
///                             scores are level and the height never changes)
///     total                  ~118 pt   (rendered: 118 at 380 pt wide)
///
/// The type size is capped at xxxLarge for the whole view (the largest sizes
/// would scale every row by up to ~1.25): at the cap the same rows render
/// about 147 pt tall, under the 160 pt limit, and `minimumScaleFactor` takes
/// over for long text instead of adding lines. The numbers come from an
/// `ImageRenderer` pass of this layout, not a device; check them on a device.
private struct LockScreenScoreboard: View {
    let attributes: PickleballActivityAttributes
    let state: PickleballActivityAttributes.ContentState
    /// The app has not updated the score for a while (see
    /// `LiveActivityController.staleAfter`), so say so instead of looking live.
    let isStale: Bool

    private var summaryLine: String {
        guard attributes.showsGamesWon else { return attributes.matchFormatSummary }
        return "\(attributes.matchFormatSummary) · Games \(state.teamAGamesWon)–\(state.teamBGamesWon)"
    }

    private var summaryAccessibilityLabel: String {
        guard attributes.showsGamesWon else { return attributes.matchFormatSummary }
        return "\(attributes.matchFormatSummary), games won \(state.teamAGamesWon) to \(state.teamBGamesWon)"
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(summaryLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(summaryAccessibilityLabel)
                Spacer(minLength: 4)
                if state.isMatchOver {
                    Text("Match Complete")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentText)
                        .lineLimit(1)
                } else if isStale {
                    Text("Out of date")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                LockScreenTeam(
                    name: attributes.teamAName,
                    score: state.teamAScore,
                    gamesWon: attributes.showsGamesWon ? state.teamAGamesWon : nil,
                    isServing: state.isTeamAServing && !state.isMatchOver,
                    servingText: servingText(state)
                )
                LockScreenTeam(
                    name: attributes.teamBName,
                    score: state.teamBScore,
                    gamesWon: attributes.showsGamesWon ? state.teamBGamesWon : nil,
                    isServing: !state.isTeamAServing && !state.isMatchOver,
                    servingText: servingText(state)
                )
            }
            // The divider is a background, not a child: as a child its flexible
            // height would let the row grow to whatever the system proposes, and
            // as a background it simply takes the height the two columns need.
            // Both columns are `minWidth: 0, maxWidth: .infinity`, so they split
            // the width equally and the divider sits exactly between them.
            .background {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Always a dark surface (see activityBackgroundTint), so resolve the
        // named colours and `.primary` for dark whatever the system appearance.
        .environment(\.colorScheme, .dark)
    }
}

private struct LockScreenTeam: View {
    let name: String
    let score: Int
    let gamesWon: Int?
    let isServing: Bool
    /// "SERVER 2" / "SERVING".
    let servingText: String

    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 54

    var body: some View {
        VStack(spacing: 0) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(score)")
                .font(.system(size: scoreSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isServing ? Color.accentText : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // A rounded font's line box is about 1.2x its size, mostly empty
                // space above and below the digits (the digits are ~0.72x the
                // size tall). Trimming the box to 0.88x the font size (the glyphs
                // overflow it symmetrically, so they stay put visually) is what
                // buys the height for a larger score.
                .frame(height: scoreSize * 0.88)
            // The serving cue is its own line under the score, not a sibling of
            // the score in an HStack: a sibling that is only hidden (opacity 0)
            // on the receiving side still takes width, which pushed the score
            // off-centre by half its width, and a trailing overlay has no room
            // beside a two-digit score in a half-width column. Both columns
            // lay out the same text, so the line is reserved at the same height
            // on both sides (the scores stay level and nothing jumps when the
            // serve changes); it is just invisible on the receiving side.
            Label(servingText, systemImage: "circle.fill")
                .font(.caption2.weight(.bold))
                .imageScale(.small)
                .foregroundStyle(Color.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(isServing ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PickleballLiveActivity.accessibilityLabel(name: name, score: score))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if isServing { parts.append(servingText.lowercased()) }
        if let gamesWon { parts.append("\(gamesWon) \(gamesWon == 1 ? "game" : "games") won") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Dynamic Island

private struct ExpandedTeam: View {
    let name: String
    let score: Int
    let isServing: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(score)")
                .font(.system(size: scoreSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isServing ? Color.accentText : Color.primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PickleballLiveActivity.accessibilityLabel(name: name, score: score))
        .accessibilityValue(isServing ? "serving" : "")
    }
}

private struct ExpandedStatus: View {
    let attributes: PickleballActivityAttributes
    let state: PickleballActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 2) {
            if state.isMatchOver {
                Text("Match Complete")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.accentText)
            } else {
                // Names which side serves (the serving score is also accented,
                // but colour alone is not a signal).
                let servingName = state.isTeamAServing ? attributes.teamAName : attributes.teamBName
                Label("\(servingName) \(servingText(state))", systemImage: "circle.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.accentText)
                    .lineLimit(1)
            }
            if attributes.showsGamesWon {
                Text("Games \(state.teamAGamesWon) - \(state.teamBGamesWon)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondaryText)
            }
        }
    }
}

private struct CompactScore: View {
    let initial: String
    let score: Int
    let isServing: Bool
    /// The mark sits on the outer edge of the island: before the score on the
    /// leading side, after it on the trailing side.
    let markFirst: Bool
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            if markFirst { mark }
            Text("\(score)")
                .font(.body.weight(isServing ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isServing ? Color.accentText : Color.primary)
            if !markFirst { mark }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isServing ? "serving" : "")
    }

    private var mark: some View {
        Text(initial)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.secondaryText)
    }
}

private struct MinimalGlyph: View {
    let state: PickleballActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.isMatchOver ? "checkmark.circle.fill" : "figure.pickleball")
            .foregroundStyle(Color.accentText)
            .accessibilityLabel(state.isMatchOver ? "Match complete" : "Match in progress")
    }
}

// MARK: - Previews

private extension PickleballActivityAttributes {
    static let previewDoubles = PickleballActivityAttributes(
        teamAName: "Alex & Sam", teamBName: "Jo & Pat",
        matchFormatSummary: "Doubles • Best of 3", showsGamesWon: true
    )
    /// Longest realistic content: doubles side-out Best of 3 with long names.
    static let previewWorstCase = PickleballActivityAttributes(
        teamAName: "Alexandra & Montgomery", teamBName: "Bartholomew & Wilhelmina",
        matchFormatSummary: "Doubles • Best of 3", showsGamesWon: true
    )
    static let previewSingles = PickleballActivityAttributes(
        teamAName: "Alex", teamBName: "Jo",
        matchFormatSummary: "Singles • Best of 1", showsGamesWon: false
    )
}

private extension PickleballActivityAttributes.ContentState {
    static let midGame = Self(
        teamAScore: 7, teamBScore: 5, teamAGamesWon: 1, teamBGamesWon: 0,
        servingTeamRawValue: "teamA", serverNumber: 2, isMatchOver: false
    )
    static let doubleDigits = Self(
        teamAScore: 10, teamBScore: 12, teamAGamesWon: 1, teamBGamesWon: 1,
        servingTeamRawValue: "teamB", serverNumber: 1, isMatchOver: false
    )
    static let worstCase = Self(
        teamAScore: 12, teamBScore: 10, teamAGamesWon: 1, teamBGamesWon: 1,
        servingTeamRawValue: "teamA", serverNumber: 2, isMatchOver: false
    )
    static let singlesRally = Self(
        teamAScore: 3, teamBScore: 4, teamAGamesWon: 0, teamBGamesWon: 0,
        servingTeamRawValue: "teamB", serverNumber: nil, isMatchOver: false
    )
    /// Worst-case content with the other team serving.
    static let worstCaseTeamB = Self(
        teamAScore: 8, teamBScore: 11, teamAGamesWon: 1, teamBGamesWon: 1,
        servingTeamRawValue: "teamB", serverNumber: 1, isMatchOver: false
    )
    static let singlesTeamA = Self(
        teamAScore: 6, teamBScore: 2, teamAGamesWon: 0, teamBGamesWon: 0,
        servingTeamRawValue: "teamA", serverNumber: nil, isMatchOver: false
    )
    static let singlesOver = Self(
        teamAScore: 11, teamBScore: 7, teamAGamesWon: 0, teamBGamesWon: 0,
        servingTeamRawValue: "teamA", serverNumber: nil, isMatchOver: true
    )
    static let matchOver = Self(
        teamAScore: 11, teamBScore: 8, teamAGamesWon: 2, teamBGamesWon: 0,
        servingTeamRawValue: "teamA", serverNumber: 1, isMatchOver: true
    )
}

#Preview("Lock Screen / StandBy", as: .content, using: PickleballActivityAttributes.previewDoubles) {
    PickleballLiveActivity()
} contentStates: {
    PickleballActivityAttributes.ContentState.midGame
    PickleballActivityAttributes.ContentState.doubleDigits
    PickleballActivityAttributes.ContentState.matchOver
}

#Preview("Lock Screen worst case", as: .content, using: PickleballActivityAttributes.previewWorstCase) {
    PickleballLiveActivity()
} contentStates: {
    PickleballActivityAttributes.ContentState.worstCase
    PickleballActivityAttributes.ContentState.worstCaseTeamB
    PickleballActivityAttributes.ContentState.matchOver
}

#Preview("Lock Screen singles", as: .content, using: PickleballActivityAttributes.previewSingles) {
    PickleballLiveActivity()
} contentStates: {
    PickleballActivityAttributes.ContentState.singlesRally
    PickleballActivityAttributes.ContentState.singlesTeamA
    PickleballActivityAttributes.ContentState.singlesOver
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: PickleballActivityAttributes.previewDoubles) {
    PickleballLiveActivity()
} contentStates: {
    PickleballActivityAttributes.ContentState.midGame
    PickleballActivityAttributes.ContentState.matchOver
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: PickleballActivityAttributes.previewDoubles) {
    PickleballLiveActivity()
} contentStates: {
    PickleballActivityAttributes.ContentState.midGame
    PickleballActivityAttributes.ContentState.doubleDigits
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: PickleballActivityAttributes.previewDoubles) {
    PickleballLiveActivity()
} contentStates: {
    PickleballActivityAttributes.ContentState.midGame
    PickleballActivityAttributes.ContentState.matchOver
}
