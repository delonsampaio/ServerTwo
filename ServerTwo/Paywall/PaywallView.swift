import SwiftUI
import SwiftData
import PickleballKit

struct PaywallView: View {
    /// Why the paywall is on screen. Only the gate may say the free match is
    /// used up: Home's banner and Settings also open it for a user who has not
    /// played anything yet.
    enum Reason {
        case demoLimitReached
        case optionalUpgrade
    }

    var reason: Reason = .optionalUpgrade

    /// Title and body for a reason; the price comes from the App Store product
    /// (localized, can change), never from a literal. A pure function so the
    /// wording is unit-tested.
    static func copy(for reason: Reason, price: String?) -> (title: String, body: String) {
        let purchase = price.map { "a one-time purchase of \($0)" } ?? "a one-time purchase"
        switch reason {
        case .demoLimitReached:
            return (
                "You've Reached the Free Demo Limit",
                "You've finished your free match. Unlock Server Two Pro with \(purchase) for unlimited matches, with no subscription. Works for your whole family with Family Sharing."
            )
        case .optionalUpgrade:
            return (
                "Unlock Server Two Pro",
                "\(price.map { "One-time purchase of \($0)" } ?? "One-time purchase") for unlimited matches, with no subscription. Works for your whole family with Family Sharing."
            )
        }
    }

    @Environment(ActiveMatchController.self) private var activeMatchController
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss
    // 48 pt at the default text size; scales with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var lockIconSize: CGFloat = 48

    var body: some View {
        NavigationStack {
            AdaptiveScroll {
                VStack(spacing: 20) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockIconSize))
                        .foregroundStyle(.tint)
                    Text(copy.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("Paywall.Title")
                    Text(copy.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondaryText)

                    purchaseSection

                    restoreSection
                }
            }
            .padding()
            .navigationTitle("Server Two Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                        // Accent TEXT on the toolbar glass (see `accentText`).
                        .tint(Color.accentText)
                        .accessibilityIdentifier("Not Now")
                }
            }
        }
        // Closes by any route that unlocks Pro: this purchase, a restore, an
        // Ask to Buy approval or a family member's purchase arriving later.
        .onChange(of: activeMatchController.proUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
        // A stale restore message from Settings must not greet a new paywall.
        .onAppear {
            storeManager.clearRestoreResult()
            // A declined Ask to Buy sends no event, so an old "waiting" or error
            // message would otherwise greet the next visit.
            storeManager.resetPurchaseState()
        }
    }

    private var copy: (title: String, body: String) {
        Self.copy(for: reason, price: storeManager.displayPrice)
    }

    @ViewBuilder
    private var purchaseSection: some View {
        switch storeManager.productState {
        case .loading:
            ProgressView()
                .accessibilityLabel("Loading price")
        case .failed:
            VStack(spacing: 12) {
                Text("Couldn't load the price from the App Store.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.errorRed)
                Button("Try Again") {
                    Task { await storeManager.loadProduct() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("Paywall.TryAgain")
            }
        case .loaded(let price):
            VStack(spacing: 12) {
                Button {
                    Task { await storeManager.purchase() }
                } label: {
                    HStack(spacing: 8) {
                        if storeManager.purchaseState == .purchasing {
                            ProgressView()
                                .accessibilityLabel("Purchasing")
                        }
                        Text("Unlock Pro — \(price)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                // Only blocked while a purchase call is running. NOT while an Ask
                // to Buy request waits: StoreKit sends nothing when a parent
                // declines, so a disabled button would strand the user.
                .disabled(storeManager.purchaseState == .purchasing)
                .accessibilityIdentifier("Paywall.UnlockPro")

                switch storeManager.purchaseState {
                case .pending:
                    Text("Waiting for approval… If the request was declined, you can try again.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondaryText)
                        .accessibilityIdentifier("Paywall.Pending")
                case .completedNotYetUnlocked:
                    Text("Purchase completed. If Pro does not unlock, tap Restore Purchases.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondaryText)
                        .accessibilityIdentifier("Paywall.CompletedNotUnlocked")
                case .failed(let message):
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.errorRed)
                        .accessibilityIdentifier("Paywall.Error")
                case .idle, .purchasing:
                    EmptyView()
                }
            }
        }
    }

    private var restoreSection: some View {
        VStack(spacing: 8) {
            Button("Restore Purchases") {
                Task { await storeManager.restorePurchases() }
            }
            .foregroundStyle(Color.accentText)
            .disabled(storeManager.isRestoring)
            .accessibilityIdentifier("Paywall.Restore")

            RestoreResultText(result: storeManager.restoreResult)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("Paywall.RestoreResult")
        }
    }
}

/// Inline outcome of Restore Purchases, shared by the paywall and Settings.
/// A successful restore shows nothing: the screen reacts to Pro unlocking.
struct RestoreResultText: View {
    let result: StoreManager.RestoreResult?

    var body: some View {
        switch result {
        case .nothingToRestore:
            Text("No previous purchase of Server Two Pro was found for this Apple Account.")
                .font(.footnote)
                .foregroundStyle(Color.secondaryText)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.errorRed)
        case .restored, .cancelled, nil:
            EmptyView()
        }
    }
}

// Debug only: the preview store is the debug fake, which Release builds do not contain.
#if DEBUG
#Preview {
    PaywallView()
        .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
        .environment(StoreManager.preview)
}
#endif
