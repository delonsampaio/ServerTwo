#if DEBUG
import StoreKit

/// Stands in for StoreKit when the app is launched by a UI test (any
/// `-UITest-` launch argument): the price is available at once, purchasing
/// unlocks without the App Store, and nothing can be restored. Debug builds only.
final class FakeStoreBackend: StoreBackend {
    /// What the fake does, chosen by `-UITest-StoreScenario <name>` so UI tests
    /// and screenshots can reach states the real store makes hard to reach.
    enum Scenario: String {
        case normal
        /// Every purchase waits for approval (Ask to Buy) and never completes.
        case pending
        case loadFails
        case purchaseFails
    }

    private struct FakeFailure: LocalizedError {
        let errorDescription: String? = "The purchase couldn't be completed. Please try again."
    }

    var displayPrice = "$1.99"
    let scenario: Scenario
    /// Tests flip this to simulate a purchase, a refund or a restore.
    var ownsPro: Bool

    init(ownsPro: Bool = false, scenario: Scenario = .normal) {
        self.ownsPro = ownsPro
        self.scenario = scenario
    }

    func loadProductDisplayPrice() async throws -> String {
        if scenario == .loadFails { throw StoreBackendError.productNotFound }
        return displayPrice
    }

    func purchase() async throws -> BackendPurchaseResult {
        switch scenario {
        case .pending: return .pending
        case .purchaseFails: throw FakeFailure()
        case .normal, .loadFails:
            ownsPro = true
            return .purchased
        }
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

extension StoreManager {
    /// For `#Preview`s: a store with the price loaded and nothing owned.
    static var preview: StoreManager { StoreManager(backend: FakeStoreBackend()) }
}
#endif
