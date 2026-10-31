import StoreKit
import PickleballKit

/// The Watch's own StoreKit 2 read of Server Two Pro (same product and Apple ID
/// as the phone). Only verified entitlements are considered, and the decision
/// is the kit's shared `ProEntitlementRule` (revoked copies never count).
/// `currentEntitlements` works from the on-device signed cache, so it does not
/// need the Watch to reach Apple's servers; the phone's pushed flag covers the
/// case where StoreKit has nothing yet.
nonisolated struct WatchStoreKitEntitlements: WatchEntitlementReading {
    func isProEntitled() async -> Bool {
        var records: [ProEntitlementRecord] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            records.append(ProEntitlementRecord(
                productID: transaction.productID, revocationDate: transaction.revocationDate
            ))
        }
        return ProEntitlementRule.isPro(from: records)
    }
}

#if DEBUG
/// Demo launches never touch StoreKit.
nonisolated struct NoWatchEntitlements: WatchEntitlementReading {
    func isProEntitled() async -> Bool { false }
}
#endif
