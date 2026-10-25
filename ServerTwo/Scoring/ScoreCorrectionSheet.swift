import SwiftUI
import PickleballKit

/// Corrects BOTH teams' scores in one step. The engine applies the pair
/// atomically (`ActiveMatchController.correctScores`), and Save is only
/// enabled for a pair live play could actually be in — a one-team-at-a-time
/// edit used to pass through boards that ended the game early or left one
/// that could never end by scoring.
struct ScoreCorrectionSheet: View {
    let teamAName: String
    let teamBName: String
    let currentTeamAScore: Int
    let currentTeamBScore: Int
    let configuration: GameConfiguration
    /// True in doubles side-out matches: the only place partner positions exist.
    let positionsEnabled: Bool
    let onCommit: (_ teamA: Int, _ teamB: Int) -> Void
    /// Called once per team whose swap changed, BEFORE `onCommit`: a score
    /// correction can end the game, and the swap belongs to the game being edited.
    let onCommitSwap: (_ team: Team, _ swapped: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 64 pt at the default text size, scaling with Dynamic Type up to a cap
    // so a two-digit score still fits its half-width card.
    @ScaledMetric(relativeTo: .largeTitle) private var scoreDigitSize: CGFloat = 64
    private let scoreDigitSizeCap: CGFloat = 88
    @State private var newTeamAScore: Int
    @State private var newTeamBScore: Int
    // Held here until Save (Cancel discards), like the scores.
    @State private var newTeamASwapped: Bool
    @State private var newTeamBSwapped: Bool
    private let currentTeamASwapped: Bool
    private let currentTeamBSwapped: Bool

    init(
        teamAName: String,
        teamBName: String,
        currentTeamAScore: Int,
        currentTeamBScore: Int,
        configuration: GameConfiguration,
        positionsEnabled: Bool = false,
        teamASwapped: Bool = false,
        teamBSwapped: Bool = false,
        onCommit: @escaping (_ teamA: Int, _ teamB: Int) -> Void,
        onCommitSwap: @escaping (_ team: Team, _ swapped: Bool) -> Void = { _, _ in }
    ) {
        self.teamAName = teamAName
        self.teamBName = teamBName
        self.currentTeamAScore = currentTeamAScore
        self.currentTeamBScore = currentTeamBScore
        self.configuration = configuration
        self.positionsEnabled = positionsEnabled
        self.onCommit = onCommit
        self.onCommitSwap = onCommitSwap
        currentTeamASwapped = teamASwapped
        currentTeamBSwapped = teamBSwapped
        _newTeamASwapped = State(initialValue: teamASwapped)
        _newTeamBSwapped = State(initialValue: teamBSwapped)
        _newTeamAScore = State(initialValue: currentTeamAScore)
        _newTeamBScore = State(initialValue: currentTeamBScore)
    }

    /// What a Save would do; nil when Save is off.
    struct SavePlan: Equatable {
        let commitsScores: Bool
        let commitsSwaps: Bool
    }

    /// Save is off while the proposed pair is unreachable (including when the
    /// CURRENT pair is already unreachable — the user must fix it) and while
    /// nothing has changed (avoids a junk undo entry). A changed swap alone
    /// enables Save and never calls the score commit, so it works even in a game
    /// whose current pair is a zombie. If the scores were edited to an
    /// unreachable pair AND a swap changed, Save stays off: committing the swap
    /// would otherwise have to quietly drop (or worse, apply) the bad scores.
    static func savePlan(
        configuration: GameConfiguration,
        currentTeamA: Int, currentTeamB: Int,
        proposedTeamA: Int, proposedTeamB: Int,
        swapChanged: Bool = false
    ) -> SavePlan? {
        let scoresChanged = proposedTeamA != currentTeamA || proposedTeamB != currentTeamB
        if scoresChanged, !configuration.isReachableGameScore(teamA: proposedTeamA, teamB: proposedTeamB) {
            return nil
        }
        guard scoresChanged || swapChanged else { return nil }
        return SavePlan(commitsScores: scoresChanged, commitsSwaps: swapChanged)
    }

    static func canSave(
        configuration: GameConfiguration,
        currentTeamA: Int, currentTeamB: Int,
        proposedTeamA: Int, proposedTeamB: Int,
        swapChanged: Bool = false
    ) -> Bool {
        savePlan(
            configuration: configuration,
            currentTeamA: currentTeamA, currentTeamB: currentTeamB,
            proposedTeamA: proposedTeamA, proposedTeamB: proposedTeamB,
            swapChanged: swapChanged
        ) != nil
    }

    /// The sheet's design height: taller when a swap control is shown. The
    /// detent is never smaller than this (see `SheetDetentPolicy.scaledHeight`).
    static func designHeight(showsSwapControl: Bool) -> CGFloat {
        showsSwapControl ? 440 : 360
    }

    static func hintText(configuration: GameConfiguration, teamA: Int, teamB: Int) -> String {
        let rule = configuration.winByTwo ? " (win by 2)" : ""
        return "\(teamA)–\(teamB) can't happen in a game to \(configuration.winningScore.rawValue)\(rule). Adjust either score."
    }

    /// What the footer shows. Always rendered (fixed height) so the sheet
    /// never jumps when the status changes. Only `.unreachable` carries the
    /// `ScoreCorrection.Hint` identifier.
    enum FooterStatus: Equatable {
        case unreachable(String)
        case endsGame
        case rule(String)
    }

    static func footerStatus(
        configuration: GameConfiguration,
        teamA: Int, teamB: Int,
        isChanged: Bool
    ) -> FooterStatus {
        if !configuration.isReachableGameScore(teamA: teamA, teamB: teamB) {
            return .unreachable(hintText(configuration: configuration, teamA: teamA, teamB: teamB))
        }
        if isChanged, configuration.isCompletedGameScore(teamA: teamA, teamB: teamB) {
            return .endsGame
        }
        let winBy = configuration.winByTwo ? " • Win by 2" : ""
        return .rule("Game to \(configuration.winningScore.rawValue)\(winBy)")
    }

    private var isChanged: Bool {
        newTeamAScore != currentTeamAScore || newTeamBScore != currentTeamBScore
    }

    private var swapChanged: Bool {
        newTeamASwapped != currentTeamASwapped || newTeamBSwapped != currentTeamBSwapped
    }

    private var savePlan: SavePlan? {
        Self.savePlan(
            configuration: configuration,
            currentTeamA: currentTeamAScore, currentTeamB: currentTeamBScore,
            proposedTeamA: newTeamAScore, proposedTeamB: newTeamBScore,
            swapChanged: swapChanged
        )
    }

    /// The positions a team would have if Save were tapped now (new score, new
    /// swap), or nil when this team has none (singles, rally, unsplit name).
    private func positions(for team: Team) -> PartnerPositions? {
        guard positionsEnabled else { return nil }
        return team == .teamA
            ? PartnerPositions.make(teamName: teamAName, score: newTeamAScore, swapped: newTeamASwapped)
            : PartnerPositions.make(teamName: teamBName, score: newTeamBScore, swapped: newTeamBSwapped)
    }

    private var showsSwapControl: Bool {
        positions(for: .teamA) != nil || positions(for: .teamB) != nil
    }

    private func save() {
        guard let plan = savePlan else { return }
        if plan.commitsSwaps {
            if newTeamASwapped != currentTeamASwapped { onCommitSwap(.teamA, newTeamASwapped) }
            if newTeamBSwapped != currentTeamBSwapped { onCommitSwap(.teamB, newTeamBSwapped) }
        }
        if plan.commitsScores { onCommit(newTeamAScore, newTeamBScore) }
        dismiss()
    }

    var body: some View {
        NavigationStack {
            AdaptiveScroll {
                VStack(spacing: 16) {
                    // Team A left, Team B right — same fixed order as ScoringView.
                    // Side by side at the default size; stacked at accessibility
                    // sizes, where two columns of +/- buttons overflow the sheet.
                    AdaptiveStack(spacing: 12) {
                        scoreColumn(
                            name: teamAName, original: currentTeamAScore, score: $newTeamAScore,
                            idPrefix: "ScoreCorrection.TeamA",
                            positions: positions(for: .teamA), swapped: $newTeamASwapped
                        )
                        scoreColumn(
                            name: teamBName, original: currentTeamBScore, score: $newTeamBScore,
                            idPrefix: "ScoreCorrection.TeamB",
                            positions: positions(for: .teamB), swapped: $newTeamBSwapped
                        )
                    }
                    footer
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .navigationTitle("Correct Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("ScoreCorrection.Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled(savePlan == nil)
                    .accessibilityIdentifier("ScoreCorrection.Save")
                }
            }
        }
        .modifier(CorrectionSheetDetents(designHeight: Self.designHeight(showsSwapControl: showsSwapControl)))
        .presentationDragIndicator(.visible)
    }

    /// One team's card. Accessibility: the numeral exposes the team name as
    /// its label and the integer score as its VALUE (tests read `.value`);
    /// the +/- buttons stay individually focusable with descriptive labels.
    private func scoreColumn(
        name: String, original: Int, score: Binding<Int>, idPrefix: String,
        positions: PartnerPositions?, swapped: Binding<Bool>
    ) -> some View {
        let value = score.wrappedValue
        let isModified = value != original
        return VStack(spacing: 6) {
            Text(name)
                .font(.headline.weight(.bold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.65)
                .multilineTextAlignment(.center)

            Text("\(value)")
                .font(.system(size: max(64, min(scoreDigitSize, scoreDigitSizeCap)), weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .foregroundStyle(isModified ? Color.accentColor : Color.primary)
                .accessibilityLabel(name)
                .accessibilityValue("\(value)")
                .accessibilityIdentifier("\(idPrefix)Score")

            Text(isModified ? "Was \(original)" : "Current")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isModified ? Color.accentColor : Color.secondary)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                Button {
                    if score.wrappedValue > 0 { score.wrappedValue -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(value <= 0)
                .accessibilityLabel("Decrease \(name)'s score")
                .accessibilityIdentifier("\(idPrefix)Decrement")

                Button {
                    if score.wrappedValue < 99 { score.wrappedValue += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(value >= 99)
                .accessibilityLabel("Increase \(name)'s score")
                .accessibilityIdentifier("\(idPrefix)Increment")
            }
            .buttonStyle(.glass)
            .buttonRepeatBehavior(.enabled)

            if showsSwapControl {
                swapControl(name: name, idPrefix: idPrefix, positions: positions, swapped: swapped)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemFill))
        )
        .overlay {
            if isModified {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .contain)
    }

    /// Partner swap for one team, with a live preview of the resulting
    /// positions. A team without positions gets an invisible copy instead, so
    /// the two columns stay the same height.
    @ViewBuilder
    private func swapControl(
        name: String, idPrefix: String, positions: PartnerPositions?, swapped: Binding<Bool>
    ) -> some View {
        let control = VStack(spacing: 2) {
            Button {
                swapped.wrappedValue.toggle()
            } label: {
                Label("Swap R/L", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Swap right and left for \(name)")
            .accessibilityIdentifier("\(idPrefix)SwapPositions")

            Text(positions?.previewText ?? " ")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("\(idPrefix)PositionsPreview")
        }
        .padding(.top, 6)
        if positions != nil {
            control
        } else {
            control.hidden().accessibilityHidden(true)
        }
    }

    private var footer: some View {
        Group {
            switch Self.footerStatus(
                configuration: configuration,
                teamA: newTeamAScore, teamB: newTeamBScore,
                isChanged: isChanged
            ) {
            case .unreachable(let text):
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("ScoreCorrection.Hint")
            case .endsGame:
                Label("Saving ends this game", systemImage: "flag.checkered")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            case .rule(let text):
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 36)
    }
}

/// This sheet already offers `.large` at the default text size, so it cannot
/// use `adaptiveSheetDetents` (the policy adds `.large` only at accessibility
/// sizes). At the default size it keeps exactly its two detents; at
/// accessibility sizes it uses the scaled height plus `.large`.
private struct CorrectionSheetDetents: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var scaledHeight: CGFloat
    private let designHeight: CGFloat

    init(designHeight: CGFloat) {
        self.designHeight = designHeight
        _scaledHeight = ScaledMetric(wrappedValue: designHeight, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.presentationDetents(Set(
                SheetDetentPolicy.detents(
                    height: SheetDetentPolicy.scaledHeight(design: designHeight, scaled: scaledHeight),
                    isAccessibilitySize: true
                )
            ))
        } else {
            content.presentationDetents([.height(designHeight), .large])
        }
    }
}

#Preview {
    ScoreCorrectionSheet(
        teamAName: "Team A",
        teamBName: "Team B",
        currentTeamAScore: 9,
        currentTeamBScore: 9,
        configuration: GameConfiguration(),
        onCommit: { _, _ in }
    )
}
