import SwiftUI
import PickleballKit

struct ScoreCorrectionSheet: View {
    let teamDisplayName: String
    let currentScore: Int
    let onCommit: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newScore: Int

    init(teamDisplayName: String, currentScore: Int, onCommit: @escaping (Int) -> Void) {
        self.teamDisplayName = teamDisplayName
        self.currentScore = currentScore
        self.onCommit = onCommit
        _newScore = State(initialValue: currentScore)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Score: \(newScore)", value: $newScore, in: 0...99)
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
