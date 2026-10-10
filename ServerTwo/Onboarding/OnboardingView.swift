import SwiftUI
import SwiftData
import PickleballKit

/// Shown once at first launch. Deliberately a single screen, not a paged
/// flow — of the three original onboarding pages, only this rule carried
/// real information (a welcome page and a generic "you're ready" closer
/// were pure friction). The full rulebook lives in Settings' "How to Play
/// Pickleball" instead, which is a comprehensive reference rather than a
/// one-time interruption.
///
/// The optional name field below is the one addition to that minimal
/// philosophy: without it, the only way to get personal stats working is
/// to type your name into a match, then separately discover Settings →
/// Manage Players → "Set as Me." Leaving it blank costs nothing — "Done"
/// behaves exactly as before — so it doesn't reintroduce the friction
/// this screen was trimmed to avoid.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var yourName: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "2.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("The First Game Starts at Server 2")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("In doubles, every game after the first starts with Server 1. But the very first game of a match is the one exception: it starts at Server 2, since there's no partner who already served and lost their turn.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Text("Server Two handles this automatically — just set up a match and start playing.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
                VStack(spacing: 8) {
                    TextField("Your Name (Optional)", text: $yourName)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("Your Name")
                    Text("Set this once so your personal win/loss record starts tracking automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveYourNameIfProvided()
                        dismiss()
                    }
                    .accessibilityIdentifier("Done")
                }
            }
        }
    }

    private func saveYourNameIfProvided() {
        let trimmed = yourName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let repository = MatchRepository(modelContext: modelContext)
        guard let player = try? repository.upsertSavedPlayer(name: trimmed) else { return }
        try? repository.setMePlayer(player)
    }
}

#Preview {
    OnboardingView()
        .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
