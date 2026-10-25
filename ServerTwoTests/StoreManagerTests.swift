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

        guard case .failed? = result else { return XCTFail("expected .failed, got \(String(describing: result))") }
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

/// A backend with scripted answers, for the outcomes `SKTestSession` cannot
/// produce (cancel, unverified, a slow stale read).
@MainActor
private final class ScriptedStoreBackend: StoreBackend {
    /// Popped per `purchase()` call; the last one repeats.
    var purchaseResults: [BackendPurchaseResult]
    /// Popped per `verifiedEntitlements()` call (each with its own delay); the
    /// last one repeats.
    var entitlementScript: [(delay: Duration, ownsPro: Bool)] = [(.zero, false)]
    var syncError: (any Error)?
    var syncDelay: Duration = .zero
    private(set) var loadProductCalls = 0

    init(purchaseResults: [BackendPurchaseResult] = [.purchased]) {
        self.purchaseResults = purchaseResults
    }

    func loadProductDisplayPrice() async throws -> String {
        loadProductCalls += 1
        return "$1.99"
    }

    func purchase() async throws -> BackendPurchaseResult {
        purchaseResults.count > 1 ? purchaseResults.removeFirst() : purchaseResults[0]
    }

    func syncWithAppStore() async throws {
        try await Task.sleep(for: syncDelay)
        if let syncError { throw syncError }
    }

    func verifiedEntitlements() async -> [VerifiedEntitlement] {
        let step = entitlementScript.count > 1 ? entitlementScript.removeFirst() : entitlementScript[0]
        try? await Task.sleep(for: step.delay)
        guard step.ownsPro else { return [] }
        return [VerifiedEntitlement(
            transactionID: 1, productID: StoreManager.proProductID,
            ownershipType: .purchased, revocationDate: nil
        )]
    }

    func runTransactionUpdates(afterFinishing: () async -> Void) async {}
}

@MainActor
final class StoreManagerPurchaseOutcomeTests: XCTestCase {
    func testACancelledPurchaseReturnsToIdleWithoutAnError() async {
        let store = StoreManager(backend: ScriptedStoreBackend(purchaseResults: [.cancelled]))
        await store.purchase()
        XCTAssertEqual(store.purchaseState, .idle)
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testAnUnverifiedPurchaseDoesNotUnlockAndShowsAMessage() async {
        let store = StoreManager(backend: ScriptedStoreBackend(purchaseResults: [.unverified]))
        await store.purchase()
        guard case .failed = store.purchaseState else {
            return XCTFail("expected a failed state, got \(store.purchaseState)")
        }
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testPendingKeepsWaiting() async {
        let store = StoreManager(backend: ScriptedStoreBackend(purchaseResults: [.pending]))
        await store.purchase()
        XCTAssertEqual(store.purchaseState, .pending)
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testADeclinedAskToBuyDoesNotBlockAnotherAttemptWhichCanSucceed() async {
        let backend = ScriptedStoreBackend(purchaseResults: [.pending, .purchased])
        let store = StoreManager(backend: backend)
        await store.purchase()
        XCTAssertEqual(store.purchaseState, .pending)

        // StoreKit sends nothing when a parent declines; the user tries again.
        backend.entitlementScript = [(.zero, true)]
        await store.purchase()
        XCTAssertEqual(store.purchaseState, .idle)
        XCTAssertTrue(store.hasProEntitlement)
    }

    func testResetPurchaseStateClearsPendingAndFailedButNotAPurchaseInProgress() async {
        let store = StoreManager(backend: ScriptedStoreBackend(purchaseResults: [.pending]))
        await store.purchase()
        store.resetPurchaseState()
        XCTAssertEqual(store.purchaseState, .idle)

        let failing = StoreManager(backend: ScriptedStoreBackend(purchaseResults: [.unverified]))
        await failing.purchase()
        failing.resetPurchaseState()
        XCTAssertEqual(failing.purchaseState, .idle)
    }

    func testAVerifiedPurchaseThatTheRefreshDoesNotShowYetIsReportedHonestly() async {
        // Purchased, but the entitlement list is still empty.
        let store = StoreManager(backend: ScriptedStoreBackend(purchaseResults: [.purchased]))
        await store.purchase()
        XCTAssertEqual(store.purchaseState, .completedNotYetUnlocked)
        XCTAssertFalse(store.hasProEntitlement)
    }

    func testAnOlderSlowRefreshCannotOverwriteANewerResult() async {
        let backend = ScriptedStoreBackend()
        // First read: slow and stale (locked). Second read: fast and fresh (entitled).
        backend.entitlementScript = [(.milliseconds(300), false), (.zero, true)]
        var results: [Bool] = []
        let store = StoreManager(backend: backend, onEntitlementChange: { results.append($0) })

        let slow = Task { await store.refreshEntitlements() }
        await Task.yield()
        await store.refreshEntitlements()
        await slow.value

        XCTAssertTrue(store.hasProEntitlement, "the fresh result must win")
        XCTAssertEqual(results, [true], "the stale result must be dropped, not applied afterwards")
    }

    func testARestoreWhoseSignInIsCancelledIsSilent() async {
        let backend = ScriptedStoreBackend()
        backend.syncError = StoreKitError.userCancelled
        let store = StoreManager(backend: backend)
        let result = await store.restorePurchases()
        XCTAssertEqual(result, .cancelled)
        XCTAssertNil(store.restoreResult, "nothing is shown for a cancelled sign-in")
    }

    func testAnotherRestoreWhileOneIsRunningDoesNothing() async {
        let backend = ScriptedStoreBackend()
        backend.syncDelay = .milliseconds(200)
        let store = StoreManager(backend: backend)
        let first = Task { await store.restorePurchases() }
        await Task.yield()
        let second = await store.restorePurchases()
        XCTAssertNil(second)
        let firstResult = await first.value
        XCTAssertEqual(firstResult, .nothingToRestore)
    }

    func testStartIsIdempotent() async {
        let backend = ScriptedStoreBackend()
        let store = StoreManager(backend: backend)
        await store.start()
        await store.start()
        XCTAssertEqual(backend.loadProductCalls, 1)
        XCTAssertEqual(store.productState, .loaded(displayPrice: "$1.99"))
    }

    func testBackendErrorsHaveReadableMessages() {
        XCTAssertNotNil(StoreBackendError.productNotFound.errorDescription)
        XCTAssertNotNil(StoreBackendError.unknownPurchaseResult.errorDescription)
    }
}

/// The wording differs by how the paywall was reached: only the gate may say
/// the free match is used up.
@MainActor
final class PaywallCopyTests: XCTestCase {
    func testTheGateSaysTheFreeMatchIsFinished() {
        let copy = PaywallView.copy(for: .demoLimitReached, price: "$1.99")
        XCTAssertEqual(copy.title, "You've Reached the Free Demo Limit")
        XCTAssertTrue(copy.body.hasPrefix("You've finished your free match."))
        XCTAssertTrue(copy.body.contains("$1.99"))
    }

    func testAnOptionalUpgradeUsesNeutralCopy() {
        let copy = PaywallView.copy(for: .optionalUpgrade, price: "$1.99")
        XCTAssertEqual(copy.title, "Unlock Server Two Pro")
        XCTAssertFalse(copy.body.contains("finished your free match"))
        XCTAssertEqual(copy.body, "One-time purchase of $1.99 for unlimited matches, with no subscription. Works for your whole family with Family Sharing.")
    }

    func testTheCopyHasNoPriceUntilItIsLoaded() {
        XCTAssertFalse(PaywallView.copy(for: .optionalUpgrade, price: nil).body.contains("$"))
        XCTAssertFalse(PaywallView.copy(for: .demoLimitReached, price: nil).body.contains("$"))
    }
}
