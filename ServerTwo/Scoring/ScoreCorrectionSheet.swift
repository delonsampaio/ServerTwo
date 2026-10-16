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

    private var isReachable: Bool {
        configuration.isReachableGameScore(teamA: newTeamAScore, teamB: newTeamBScore)
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
            Form {
                Section {
                    Stepper("\(teamAName): \(newTeamAScore)", value: $newTeamAScore, in: 0...99)
                        .accessibilityIdentifier("ScoreCorrection.TeamAStepper")
                    Stepper("\(teamBName): \(newTeamBScore)", value: $newTeamBScore, in: 0...99)
                        .accessibilityIdentifier("ScoreCorrection.TeamBStepper")
                }
                if !isReachable {
                    Section {
                        Text(Self.hintText(configuration: configuration, teamA: newTeamAScore, teamB: newTeamBScore))
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("ScoreCorrection.Hint")
                    }
                }
            }
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
        .presentationDetents([.medium])
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
