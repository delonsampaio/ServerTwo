import XCTest
import StoreKit
import StoreKitTest
@testable import ServerTwo

/// The pure entitlement decision, with every ownership type and revocation case.
final class ProEntitlementEvaluatorTests: XCTestCase {
    private func entitlement(
        id: UInt64 = 1,
        product: String = StoreManager.proProductID,
        ownership: Transaction.OwnershipType,
        revoked: Bool = false
    ) -> VerifiedEntitlement {
        VerifiedEntitlement(
            transactionID: id,
            productID: product,
            ownershipType: ownership,
            revocationDate: revoked ? Date(timeIntervalSince1970: 1_000) : nil
        )
    }

    func testNoEntitlementsMeansLocked() {
        XCTAssertFalse(StoreManager.isProEntitled(from: []))
    }

    func testAPurchasedCopyUnlocks() {
        XCTAssertTrue(StoreManager.isProEntitled(from: [entitlement(ownership: .purchased)]))
    }

    func testAFamilySharedCopyUnlocksTheSameWay() {
        XCTAssertTrue(StoreManager.isProEntitled(from: [entitlement(ownership: .familyShared)]))
    }

    func testARevokedFamilySharedCopyDoesNotUnlock() {
        XCTAssertFalse(StoreManager.isProEntitled(from: [entitlement(ownership: .familyShared, revoked: true)]))
    }

    func testARevokedFamilySharedCopyDoesNotLockAUserWithAValidPurchase() {
        XCTAssertTrue(StoreManager.isProEntitled(from: [
            entitlement(id: 1, ownership: .familyShared, revoked: true),
            entitlement(id: 2, ownership: .purchased),
        ]))
    }

    func testAnotherProductDoesNotUnlock() {
        XCTAssertFalse(StoreManager.isProEntitled(from: [entitlement(product: "com.example.other", ownership: .purchased)]))
    }

    func testARevokedPurchaseDoesNotUnlock() {
        XCTAssertFalse(StoreManager.isProEntitled(from: [entitlement(ownership: .purchased, revoked: true)]))
    }
}

/// `StoreManager` against the real StoreKit code paths, driven by an
/// `SKTestSession` loaded from `Products.storekit` (no App Store involved).
@MainActor
final class StoreManagerStoreKitTests: XCTestCase {
    private var session: SKTestSession!
    private var store: StoreManager!
    private var entitlementChanges: [Bool] = []

    override func setUp() async throws {
        try await super.setUp()
        let url = try XCTUnwrap(
            Bundle(for: StoreManagerStoreKitTests.self).url(forResource: "Products", withExtension: "storekit"),
            "Products.storekit must be in the test bundle"
        )
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        entitlementChanges = []
        store = StoreManager(backend: StoreKitBackend(), onEntitlementChange: { [weak self] in
            self?.entitlementChanges.append($0)
        })
    }

    override func tearDown() async throws {
        store = nil
        session?.clearTransactions()
        session = nil
        try await super.tearDown()
    }

    /// Polls because the Transaction.updates listener delivers asynchronously.
    private func waitUntil(timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    private var proTransaction: SKTestTransaction? {
        session.allTransactions().first { $0.productIdentifier == StoreManager.proProductID }
    }

    func testTheProductLoadsWithItsLocalizedPrice() async throws {
        await store.start()
        XCTAssertEqual(store.productState, .loaded(displayPrice: "$1.99"))
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testASuccessfulPurchaseUnlocksAndRecordsAVerifiedTransaction() async throws {
        await store.start()
        await store.purchase()

        XCTAssertTrue(store.hasProEntitlement)
        XCTAssertEqual(store.purchaseState, .idle)
        XCTAssertEqual(entitlementChanges.last, true)
        XCTAssertNotNil(proTransaction)
        // `transaction.finish()` is called on the verified result in
        // `StoreKitBackend.purchase`. Asserting it through
        // `Transaction.unfinished` proved unreliable: it passed when this test
        // ran alone and listed the new transaction as unfinished inside the
        // whole suite (StoreKit test daemon state shared across tests). An
        // unfinished Pro transaction is harmless here either way, because the
        // updates listener finishes every verified Pro transaction it receives.
    }

    // No SKTestSession test for "user cancelled": the session cannot simulate
    // it (`.generic(.userCancelled)` surfaces as `StoreKitError.unknown`), so
    // the cancelled/unverified mapping is covered with `ScriptedStoreBackend`
    // in `StoreManagerPurchaseOutcomeTests` below.

    func testAPurchaseErrorShowsAFailedStateAndDoesNotUnlock() async throws {
        await store.start()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        await store.purchase()
        try await session.setSimulatedError(nil, forAPI: .purchase)

        guard case .failed = store.purchaseState else {
            return XCTFail("expected a failed purchase state, got \(store.purchaseState)")
        }
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testAskToBuyWaitsThenUnlocksWhenApproved() async throws {
        await store.start()
        session.askToBuyEnabled = true
        await store.purchase()

        XCTAssertEqual(store.purchaseState, .pending)
        XCTAssertFalse(store.hasProEntitlement)

        let pending = try XCTUnwrap(proTransaction)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)

        let unlocked = await waitUntil { self.store.hasProEntitlement }
        XCTAssertTrue(unlocked, "the updates listener should unlock once the request is approved")
        XCTAssertEqual(store.purchaseState, .idle)
        XCTAssertEqual(entitlementChanges.last, true)
    }

    func testARefundRelocks() async throws {
        await store.start()
        await store.purchase()
        XCTAssertTrue(store.hasProEntitlement)

        let transaction = try XCTUnwrap(proTransaction)
        try session.refundTransaction(identifier: transaction.identifier)

        let relocked = await waitUntil { !self.store.hasProEntitlement }
        XCTAssertTrue(relocked, "a refund must lock Pro again")
        XCTAssertEqual(entitlementChanges.last, false)
    }

    func testRestoreWithNoPurchaseFindsNothing() async throws {
        await store.start()
        let result = await store.restorePurchases()
        XCTAssertEqual(result, .nothingToRestore)
        XCTAssertEqual(store.restoreResult, .nothingToRestore)
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testRestoreFindsAnExistingPurchase() async throws {
        // Bought outside this StoreManager (like on another device).
        _ = try await session.buyProduct(identifier: StoreManager.proProductID)
        let result = await store.restorePurchases()
        XCTAssertEqual(result, .restored)
        XCTAssertTrue(store.hasProEntitlement)
        XCTAssertEqual(entitlementChanges.last, true)
    }

    func testAnEntitlementPresentAtLaunchUnlocksAfterStart() async throws {
        _ = try await session.buyProduct(identifier: StoreManager.proProductID)
        await store.start()
        XCTAssertTrue(store.hasProEntitlement)
    }

    func testAProductLoadFailureCanBeRetried() async throws {
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await store.start()
        XCTAssertEqual(store.productState, .failed)

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.loadProduct()
        XCTAssertEqual(store.productState, .loaded(displayPrice: "$1.99"))
    }

    func testAFailedRestoreReportsTheFailure() async throws {
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)
        let result = await store.restorePurchases()
        try await session.setSimulatedError(nil, forAPI: .appStoreSync)

        guard case .failed = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertFalse(store.hasProEntitlement)
    }
}

@MainActor
final class MyAppStoreBackendTests: XCTestCase {
    func testUITestLaunchArgumentsSelectTheFakeStore() {
        XCTAssertTrue(MyApp.makeStoreBackend(arguments: ["-UITest-ResetState"]) is FakeStoreBackend)
    }

    func testANormalLaunchUsesRealStoreKit() {
        XCTAssertTrue(MyApp.makeStoreBackend(arguments: ["ServerTwo"]) is StoreKitBackend)
    }
}

/// A backend that returns a scripted purchase result, for the outcomes
/// `SKTestSession` cannot produce (cancel, unverified).
@MainActor
private final class ScriptedStoreBackend: StoreBackend {
    var purchaseResult: BackendPurchaseResult
    init(purchaseResult: BackendPurchaseResult) { self.purchaseResult = purchaseResult }
    func loadProductDisplayPrice() async throws -> String { "$1.99" }
    func purchase() async throws -> BackendPurchaseResult { purchaseResult }
    func syncWithAppStore() async throws {}
    func verifiedEntitlements() async -> [VerifiedEntitlement] { [] }
    func runTransactionUpdates(afterFinishing: () async -> Void) async {}
}

@MainActor
final class StoreManagerPurchaseOutcomeTests: XCTestCase {
    func testACancelledPurchaseReturnsToIdleWithoutAnError() async {
        let store = StoreManager(backend: ScriptedStoreBackend(purchaseResult: .cancelled))
        await store.purchase()
        XCTAssertEqual(store.purchaseState, .idle)
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testAnUnverifiedPurchaseDoesNotUnlockAndShowsAMessage() async {
        let store = StoreManager(backend: ScriptedStoreBackend(purchaseResult: .unverified))
        await store.purchase()
        guard case .failed = store.purchaseState else {
            return XCTFail("expected a failed state, got \(store.purchaseState)")
        }
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testPendingKeepsWaiting() async {
        let store = StoreManager(backend: ScriptedStoreBackend(purchaseResult: .pending))
        await store.purchase()
        XCTAssertEqual(store.purchaseState, .pending)
        XCTAssertFalse(store.hasProEntitlement)
    }
}
