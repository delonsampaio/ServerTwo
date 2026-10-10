import SwiftUI

/// Shown once at first launch. Deliberately a single screen, not a paged
/// flow — of the three original onboarding pages, only this rule carried
/// real information (a welcome page and a generic "you're ready" closer
/// were pure friction). The full rulebook lives in Settings' "How to Play
/// Pickleball" instead, which is a comprehensive reference rather than a
/// one-time interruption.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

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
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("Done")
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
