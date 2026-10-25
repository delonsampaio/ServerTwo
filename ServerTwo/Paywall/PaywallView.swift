import SwiftUI
import SwiftData
import PickleballKit

struct PaywallView: View {
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
                    Text("You've Reached the Free Demo Limit")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(bodyText)
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
        .onAppear { storeManager.clearRestoreResult() }
    }

    /// The price always comes from the App Store product (it is localized and
    /// can change), never from a literal.
    private var bodyText: String {
        let purchase = storeManager.displayPrice.map { "a one-time purchase of \($0)" } ?? "a one-time purchase"
        return "You've finished your free match. Unlock Server Two Pro with \(purchase) for unlimited matches, with no subscription. Works for your whole family with Family Sharing."
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
                // Not offered again while a purchase runs, or while an Ask to
                // Buy request waits (a second tap would only create another).
                .disabled(storeManager.purchaseState == .purchasing || storeManager.purchaseState == .pending)
                .accessibilityIdentifier("Paywall.UnlockPro")

                switch storeManager.purchaseState {
                case .pending:
                    Text("Waiting for approval…")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondaryText)
                        .accessibilityIdentifier("Paywall.Pending")
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
        case .restored, nil:
            EmptyView()
        }
    }
}

#Preview {
    PaywallView()
        .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
        .environment(StoreManager(backend: StoreKitBackend()))
}
