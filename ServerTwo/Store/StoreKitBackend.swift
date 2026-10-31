import StoreKit
import os

/// The real StoreKit 2 implementation of `StoreBackend`.
final class StoreKitBackend: StoreBackend {
    private var product: Product?
    /// Console: subsystem com.delonsampaio.ServerTwo, category Store. Product ids
    /// and verification outcomes only, nothing personal.
    private let log = Logger(subsystem: "com.delonsampaio.ServerTwo", category: "Store")

    func loadProductDisplayPrice() async throws -> String {
        let products = try await Product.products(for: [StoreManager.proProductID])
        guard let pro = products.first(where: { $0.id == StoreManager.proProductID }) else {
            throw StoreBackendError.productNotFound
        }
        product = pro
        return pro.displayPrice
    }

    func purchase() async throws -> BackendPurchaseResult {
        guard let product else { throw StoreBackendError.productNotFound }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch StoreKitError.userCancelled {
            // Some StoreKit paths surface a cancel as a thrown error instead
            // of `.userCancelled`; either way it is not a failure to report.
            log.info("purchase: thrown userCancelled")
            return .cancelled
        } catch {
            log.error("purchase: threw \(String(describing: error), privacy: .public)")
            throw error
        }
        switch result {
        case .success(.verified(let transaction)):
            log.info("purchase: verified transaction for \(transaction.productID, privacy: .public), revoked: \(transaction.revocationDate != nil)")
            // Only a verified transaction may be finished; an unverified one
            // stays unfinished so StoreKit keeps offering it to us.
            await transaction.finish()
            return .purchased
        case .success(.unverified(_, let error)):
            log.error("purchase: UNVERIFIED transaction: \(String(describing: error), privacy: .public)")
            return .unverified
        case .pending:
            log.info("purchase: pending")
            return .pending
        case .userCancelled:
            log.info("purchase: userCancelled")
            return .cancelled
        @unknown default:
            throw StoreBackendError.unknownPurchaseResult
        }
    }

    func syncWithAppStore() async throws {
        try await AppStore.sync()
    }

    func verifiedEntitlements() async -> [VerifiedEntitlement] {
        var entitlements: [VerifiedEntitlement] = []
        for await result in Transaction.currentEntitlements {
            // Unverified entitlements are ignored: they must never unlock.
            guard case .verified(let transaction) = result else {
                if case .unverified(let transaction, let error) = result {
                    log.error("entitlements: ignoring UNVERIFIED \(transaction.productID, privacy: .public): \(String(describing: error), privacy: .public)")
                }
                continue
            }
            entitlements.append(VerifiedEntitlement(
                transactionID: transaction.id,
                productID: transaction.productID,
                ownershipType: transaction.ownershipType,
                revocationDate: transaction.revocationDate
            ))
        }
        log.info("entitlements: \(entitlements.count) verified: \(entitlements.map(\.productID).joined(separator: ","), privacy: .public)")
        return entitlements
    }

    func runTransactionUpdates(afterFinishing: () async -> Void) async {
        for await result in Transaction.updates {
            log.info("updates: received a transaction update")
            // Unverified updates and other products are neither trusted nor
            // finished.
            guard case .verified(let transaction) = result,
                  transaction.productID == StoreManager.proProductID else { continue }
            await transaction.finish()
            // The caller re-reads every entitlement instead of trusting this
            // one transaction: a revoked family-shared copy must not lock a
            // user who also owns a valid direct purchase.
            await afterFinishing()
        }
    }
}
