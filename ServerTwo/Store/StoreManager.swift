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
        /// Ask to Buy: waiting for approval, which arrives via the updates
        /// listener. StoreKit sends nothing when a parent DECLINES, so this
        /// state never blocks another attempt.
        case pending
        /// StoreKit said the purchase succeeded but the entitlement refresh does
        /// not show it yet; the user is pointed at Restore Purchases.
        case completedNotYetUnlocked
        case failed(String)
    }

    enum RestoreResult: Equatable {
        case restored
        case nothingToRestore
        case failed(String)
        /// The user dismissed the App Store sign-in: neutral, nothing to show.
        case cancelled
    }

    private(set) var productState: ProductState = .loading
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var isRestoring = false
    /// The latest restore outcome, shown inline by the paywall and Settings.
    private(set) var restoreResult: RestoreResult?
    private(set) var hasProEntitlement = false

    /// Refreshes can overlap (updates listener, launch, purchase, restore). Each
    /// takes a ticket before it awaits and its result is applied only if no
    /// newer refresh has already applied one, so a slow older read can never
    /// overwrite a newer result.
    @ObservationIgnored private var lastIssuedRefreshTicket = 0
    @ObservationIgnored private var lastAppliedRefreshTicket = 0
    @ObservationIgnored private var hasStarted = false

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

    /// Launch work: the entitlement that may have changed while the app was
    /// closed, and the price for the paywall. Idempotent (a `.task` can run once
    /// per window), and the two run concurrently so the paywall does not wait
    /// for the entitlement read before it can show the price.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        async let entitlements: Void = refreshEntitlements()
        async let product: Void = loadProduct()
        _ = await (entitlements, product)
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
        lastIssuedRefreshTicket += 1
        let ticket = lastIssuedRefreshTicket
        let entitlements = await backend.verifiedEntitlements()
        guard ticket > lastAppliedRefreshTicket else { return }
        lastAppliedRefreshTicket = ticket
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
                // Keep the state honest if StoreKit's own entitlement list does
                // not show the purchase yet (instead of silently doing nothing).
                if !hasProEntitlement { purchaseState = .completedNotYetUnlocked }
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

    /// Clears a stale pending / failed message when the paywall appears (a
    /// declined Ask to Buy never produces an event that would clear it).
    func resetPurchaseState() {
        switch purchaseState {
        case .pending, .failed, .completedNotYetUnlocked: purchaseState = .idle
        case .idle, .purchasing: break
        }
    }

    // MARK: Restore

    /// Returns nil when a restore is already running (this call does nothing).
    @discardableResult
    func restorePurchases() async -> RestoreResult? {
        guard !isRestoring else { return nil }
        isRestoring = true
        defer { isRestoring = false }
        restoreResult = nil
        let result: RestoreResult
        do {
            try await backend.syncWithAppStore()
            await refreshEntitlements()
            result = hasProEntitlement ? .restored : .nothingToRestore
        } catch StoreKitError.userCancelled {
            // Dismissing the App Store sign-in is a choice, not an error.
            result = .cancelled
        } catch {
            result = .failed("Couldn't restore purchases. Check your connection and try again.")
        }
        restoreResult = result == .cancelled ? nil : result
        return result
    }

    func clearRestoreResult() {
        restoreResult = nil
    }
}
