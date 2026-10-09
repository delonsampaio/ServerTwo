import SwiftUI
import PickleballKit

struct ScoreCorrectionSheet: View {
    let teamDisplayName: String
    let currentScore: Int
    /// Upper bound for the stepper. Defaults to `99` so call sites that have
    /// no cap concern are unaffected; `ScoringView` passes the demo cap for
    /// locked users, because `PickleballGame.correctScore` doesn't enforce
    /// the demo-cap paywall the way `recordPoint` does (existing
    /// `PickleballKit` behavior) — without this bound a free user could
    /// correct straight past the cap to a winning score.
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
