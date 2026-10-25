import StoreKit

/// One verified entitlement as `StoreManager` evaluates it: just the fields
/// the unlock decision needs, so the decision is a pure function that can be
/// tested without StoreKit transactions (which cannot be constructed by hand).
nonisolated struct VerifiedEntitlement: Sendable, Equatable {
    let transactionID: UInt64
    let productID: String
    let ownershipType: Transaction.OwnershipType
    /// Non-nil once the purchase was refunded or a family-shared copy was
    /// revoked (the member left the family or the organiser stopped sharing).
    let revocationDate: Date?
}

/// What a purchase attempt ended as, before `StoreManager` turns it into UI state.
enum BackendPurchaseResult: Equatable {
    /// Verified, and the transaction has been finished.
    case purchased
    /// Ask to Buy: the purchase waits for a parent's approval.
    case pending
    case cancelled
    /// StoreKit returned a transaction whose signature did not verify.
    case unverified
}

enum StoreBackendError: Error, Equatable {
    case productNotFound
    case unknownPurchaseResult
}

/// The thin StoreKit surface `StoreManager` talks to. It exists so UI tests
/// run against `FakeStoreBackend` (never the App Store), while the real
/// `StoreKitBackend` is exercised by `SKTestSession` unit tests.
protocol StoreBackend: AnyObject {
    /// Loads the Pro product and returns its localized display price.
    func loadProductDisplayPrice() async throws -> String
    func purchase() async throws -> BackendPurchaseResult
    /// `AppStore.sync()`; the caller re-reads the entitlements afterwards.
    func syncWithAppStore() async throws
    /// Every verified entitlement StoreKit currently reports (works offline
    /// from the on-device signed cache; refunded purchases are omitted).
    func verifiedEntitlements() async -> [VerifiedEntitlement]
    /// Runs until cancelled: for each verified Pro transaction that arrives
    /// outside a purchase call (Ask to Buy approval, a family member's
    /// purchase, a refund), finishes it and then calls `afterFinishing`.
    func runTransactionUpdates(afterFinishing: () async -> Void) async
}
