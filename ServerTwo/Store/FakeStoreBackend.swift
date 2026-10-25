#if DEBUG
import StoreKit

/// Stands in for StoreKit when the app is launched by a UI test (any
/// `-UITest-` launch argument): the price is available at once, purchasing
/// unlocks without the App Store, and nothing can be restored. Debug builds only.
final class FakeStoreBackend: StoreBackend {
    var displayPrice = "$1.99"
    /// Tests flip this to simulate a purchase, a refund or a restore.
    var ownsPro: Bool

    init(ownsPro: Bool = false) {
        self.ownsPro = ownsPro
    }

    func loadProductDisplayPrice() async throws -> String { displayPrice }

    func purchase() async throws -> BackendPurchaseResult {
        ownsPro = true
        return .purchased
    }

    func syncWithAppStore() async throws {}

    func verifiedEntitlements() async -> [VerifiedEntitlement] {
        guard ownsPro else { return [] }
        return [VerifiedEntitlement(
            transactionID: 1,
            productID: StoreManager.proProductID,
            ownershipType: .purchased,
            revocationDate: nil
        )]
    }

    /// There is no update stream to watch.
    func runTransactionUpdates(afterFinishing: () async -> Void) async {}
}
#endif
