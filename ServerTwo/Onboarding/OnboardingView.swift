import SwiftUI
import SwiftData
import PickleballKit

/// Shown once at first launch. Deliberately a single screen, not a paged
/// flow, and it says what the app does rather than teaching pickleball:
/// people downloading a scorekeeper already know the rules, and the full
/// rulebook lives in Settings' "How to Play Pickleball" for anyone who
/// wants it.
///
/// The optional name field below is the one piece of setup: without it,
/// the only way to get personal stats working is to type your name into a
/// match, then separately discover Settings → Manage Players → "Set as
/// Me." Leaving it blank costs nothing — "Done" behaves exactly as before
/// — so it doesn't reintroduce the friction this screen was trimmed to
/// avoid.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    /// Explicitly passed in by `MyApp`, not read via `@Environment(\.modelContext)`.
    /// This view is presented via `.sheet`, and `@Environment(\.modelContext)`
    /// was confirmed (via direct instrumentation: insert + save reported no
    /// error, yet an immediate re-fetch in the very same function, against
    /// the very same context, returned zero rows — even with a 15-second
    /// delay first, ruling out any startup/CloudKit-readiness timing
    /// explanation) to resolve to a context not backed by the app's real
    /// store for sheet content here. Taking the container's `mainContext`
    /// directly sidesteps whatever that resolution gap is — the same
    /// defensive move `ActiveMatchController` already makes for its own
    /// context, for an analogous reliability reason.
    let modelContext: ModelContext
    @State private var yourName: String = ""
    // 64 pt and 32 pt at the default text size; they scale with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title2) private var featureIconWidth: CGFloat = 32

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "figure.pickleball")
                        .font(.system(size: heroIconSize))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Welcome to Server Two")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text("Score singles and doubles matches point by point. Server Two keeps track of who's serving, which side everyone's on, and your stats over time.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondaryText)

                    VStack(alignment: .leading, spacing: 16) {
                        featureRow(
                            icon: "arrow.left.arrow.right.circle.fill",
                            title: "Automatic Court Positions",
                            detail: "Doubles side-out games show which partner is on the left or right. Hold a score card to swap them if you started the other way round."
                        )
                        featureRow(
                            icon: "hand.tap.fill",
                            title: "Tap to Score, Hold to Correct",
                            detail: "Tap a card to score a point, or press and hold to fix a disputed score."
                        )
                        featureRow(
                            icon: "person.2.fill",
                            title: "Partner & Rival Chemistry",
                            detail: "See your record with every partner and against every rival."
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            TextField("Your Name (Optional)", text: $yourName)
                                .accessibilityIdentifier("Your Name")
                        }
                        .padding(14)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text("Set this once so your personal win/loss record starts tracking automatically.")
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    // Deliberately NOT identified "Done": the toolbar button owns
                    // that identifier, which every UI test's
                    // `dismissOnboardingIfPresented` taps.
                    Button {
                        finish()
                    } label: {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("Get Started")
                }
                .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        finish()
                    }
                    // Accent TEXT on the toolbar glass (see `accentText`).
                    .tint(Color.accentText)
                    .accessibilityIdentifier("Done")
                }
            }
        }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: featureIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func finish() {
        saveYourNameIfProvided()
        dismiss()
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
    let container = try! PersistenceContainer.makeInMemoryContainer()
    return OnboardingView(modelContext: container.mainContext)
        .modelContainer(container)
}
