import StoreKit
import Observation

/// Owns the Server Two Pro purchase: product loading, purchase, restore and
/// the entitlement decision. Created once in `MyApp`.
///
/// The entitlement is always recomputed from ALL current entitlements (never
/// flipped from a single transaction), and the result is pushed to
/// `onEntitlementChange`, which keeps `ActiveMatchController.proUnlocked` (the
/// only thing the rest of the app reads) in step.
@MainActor
@Observable
final class StoreManager {
    /// Non-consumable, Family Sharing on.
    nonisolated static let proProductID = "com.delonsampaio.ServerTwo.pro"

    enum ProductState: Equatable {
        case loading
        case loaded(displayPrice: String)
        case failed
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        /// Ask to Buy: waiting for approval, which arrives via the updates listener.
        case pending
        case failed(String)
    }

    enum RestoreResult: Equatable {
        case restored
        case nothingToRestore
        case failed(String)
    }

    private(set) var productState: ProductState = .loading
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var isRestoring = false
    /// The latest restore outcome, shown inline by the paywall and Settings.
    private(set) var restoreResult: RestoreResult?
    private(set) var hasProEntitlement = false

    private let backend: any StoreBackend
    private let onEntitlementChange: @MainActor (Bool) -> Void
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// - Parameter onEntitlementChange: called after every entitlement refresh
    ///   with the unconditional result (an empty entitlement list means `false`).
    init(
        backend: any StoreBackend,
        onEntitlementChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.backend = backend
        self.onEntitlementChange = onEntitlementChange
        // Lives as long as the app: purchases can complete outside the paywall
        // (Ask to Buy approval, a family member's purchase, a refund).
        updatesTask = Task { [weak self, backend] in
            await backend.runTransactionUpdates {
                await self?.refreshEntitlements()
            }
        }
    }

    isolated deinit {
        updatesTask?.cancel()
    }

    /// Launch work: price for the paywall, and the entitlement that may have
    /// changed while the app was closed.
    func start() async {
        await refreshEntitlements()
        await loadProduct()
    }

    // MARK: Entitlement

    /// True iff some entry is the Pro product and has not been revoked. A
    /// directly purchased copy and a family-shared copy count the same, and a
    /// revoked copy never counts, so a refund or a family member leaving
    /// re-locks while a still-valid second copy keeps Pro.
    nonisolated static func isProEntitled(from entitlements: [VerifiedEntitlement]) -> Bool {
        entitlements.contains { $0.productID == proProductID && $0.revocationDate == nil }
    }

    func refreshEntitlements() async {
        let entitlements = await backend.verifiedEntitlements()
        // Set unconditionally: an empty list means locked, so a stale `true`
        // (for example after a refund) is never kept.
        let entitled = Self.isProEntitled(from: entitlements)
        hasProEntitlement = entitled
        if entitled { purchaseState = .idle }
        onEntitlementChange(entitled)
    }

    // MARK: Product

    func loadProduct() async {
        productState = .loading
        do {
            productState = .loaded(displayPrice: try await backend.loadProductDisplayPrice())
        } catch {
            productState = .failed
        }
    }

    /// The price once loaded, for rows that only show it when known.
    var displayPrice: String? {
        if case .loaded(let price) = productState { return price }
        return nil
    }

    // MARK: Purchase

    func purchase() async {
        guard purchaseState != .purchasing else { return }
        purchaseState = .purchasing
        do {
            switch try await backend.purchase() {
            case .purchased:
                purchaseState = .idle
                await refreshEntitlements()
            case .pending:
                purchaseState = .pending
            case .cancelled:
                purchaseState = .idle
            case .unverified:
                // Not unlocked and not finished: see `StoreKitBackend`.
                purchaseState = .failed("The App Store couldn't verify this purchase, so Pro was not unlocked. Please try again, or tap Restore Purchases.")
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: Restore

    @discardableResult
    func restorePurchases() async -> RestoreResult {
        isRestoring = true
        defer { isRestoring = false }
        restoreResult = nil
        let result: RestoreResult
        do {
            try await backend.syncWithAppStore()
            await refreshEntitlements()
            result = hasProEntitlement ? .restored : .nothingToRestore
        } catch {
            result = .failed("Couldn't restore purchases. Check your connection and try again.")
        }
        restoreResult = result
        return result
    }

    func clearRestoreResult() {
        restoreResult = nil
    }
}
