import SwiftUI
import PickleballKit

struct ScoreCorrectionSheet: View {
    let teamDisplayName: String
    let currentScore: Int
    /// Upper bound for the stepper. Defaults to `99`; no call site currently
    /// needs a tighter cap, since the demo gate now lives at match-start
    /// (`ActiveMatchController.canStartNewMatch`), not on in-game scores.
    let maxScore: Int
    let onCommit: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newScore: Int

    init(teamDisplayName: String, currentScore: Int, maxScore: Int = 99, onCommit: @escaping (Int) -> Void) {
        self.teamDisplayName = teamDisplayName
        self.currentScore = currentScore
        self.maxScore = maxScore
        self.onCommit = onCommit
        _newScore = State(initialValue: currentScore)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Score: \(newScore)", value: $newScore, in: 0...maxScore)
            }
            .navigationTitle("Correct \(teamDisplayName)'s Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onCommit(newScore)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ScoreCorrectionSheet(teamDisplayName: "Team A", currentScore: 7, onCommit: { _ in })
}
