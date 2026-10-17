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
    let onCommit: (_ teamA: Int, _ teamB: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newTeamAScore: Int
    @State private var newTeamBScore: Int

    init(
        teamAName: String,
        teamBName: String,
        currentTeamAScore: Int,
        currentTeamBScore: Int,
        configuration: GameConfiguration,
        onCommit: @escaping (_ teamA: Int, _ teamB: Int) -> Void
    ) {
        self.teamAName = teamAName
        self.teamBName = teamBName
        self.currentTeamAScore = currentTeamAScore
        self.currentTeamBScore = currentTeamBScore
        self.configuration = configuration
        self.onCommit = onCommit
        _newTeamAScore = State(initialValue: currentTeamAScore)
        _newTeamBScore = State(initialValue: currentTeamBScore)
    }

    /// Save is off while the pair is unreachable (including when the CURRENT
    /// pair is already unreachable — the user must fix it) and while nothing
    /// has changed (avoids a junk undo entry).
    static func canSave(
        configuration: GameConfiguration,
        currentTeamA: Int, currentTeamB: Int,
        proposedTeamA: Int, proposedTeamB: Int
    ) -> Bool {
        let isUnchanged = proposedTeamA == currentTeamA && proposedTeamB == currentTeamB
        return !isUnchanged && configuration.isReachableGameScore(teamA: proposedTeamA, teamB: proposedTeamB)
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

    private var canSave: Bool {
        Self.canSave(
            configuration: configuration,
            currentTeamA: currentTeamAScore, currentTeamB: currentTeamBScore,
            proposedTeamA: newTeamAScore, proposedTeamB: newTeamBScore
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Team A left, Team B right — same fixed order as ScoringView.
                HStack(spacing: 12) {
                    scoreColumn(
                        name: teamAName, original: currentTeamAScore, score: $newTeamAScore,
                        idPrefix: "ScoreCorrection.TeamA"
                    )
                    scoreColumn(
                        name: teamBName, original: currentTeamBScore, score: $newTeamBScore,
                        idPrefix: "ScoreCorrection.TeamB"
                    )
                }
                footer
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
                    Button("Save") {
                        onCommit(newTeamAScore, newTeamBScore)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("ScoreCorrection.Save")
                }
            }
        }
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
    }

    /// One team's card. Accessibility: the numeral exposes the team name as
    /// its label and the integer score as its VALUE (tests read `.value`);
    /// the +/- buttons stay individually focusable with descriptive labels.
    private func scoreColumn(
        name: String, original: Int, score: Binding<Int>, idPrefix: String
    ) -> some View {
        let value = score.wrappedValue
        let isModified = value != original
        return VStack(spacing: 6) {
            Text(name)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text("\(value)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
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
