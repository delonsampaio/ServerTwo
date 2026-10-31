import XCTest
import os
@testable import PickleballKit

final class WatchDemoGateTests: XCTestCase {
    func testTheLimitIsOneMatchLikeThePhone() {
        XCTAssertEqual(WatchDemoGate.demoMatchLimit, 1)
    }

    func testTruthTable() {
        // (isPro, local, phone) -> allowed, with limit 1.
        let table: [(Bool, Int, Int, Bool)] = [
            (false, 0, 0, true),
            (false, 1, 0, false),
            (false, 0, 1, false),
            (false, 1, 1, false),
            (false, 5, 7, false),
            (true, 0, 0, true),
            (true, 1, 0, true),
            (true, 0, 9, true),
        ]
        for (isPro, local, phone, expected) in table {
            XCTAssertEqual(
                WatchDemoGate.canStartMatch(isPro: isPro, localCount: local, phoneCount: phone, limit: 1), expected,
                "pro \(isPro) local \(local) phone \(phone)"
            )
        }
    }

    func testAHigherLimitIsHonoured() {
        XCTAssertTrue(WatchDemoGate.canStartMatch(isPro: false, localCount: 1, phoneCount: 2, limit: 3))
        XCTAssertFalse(WatchDemoGate.canStartMatch(isPro: false, localCount: 1, phoneCount: 3, limit: 3))
    }

    func testTheBudgetIsTheLargerCountNotTheSum() {
        // One match played on the watch and already imported by the phone is
        // one match, not two (limit 2 would otherwise block).
        XCTAssertTrue(WatchDemoGate.canStartMatch(isPro: false, localCount: 1, phoneCount: 1, limit: 2))
    }
}

final class WatchLifetimeCounterTests: XCTestCase {
    func testStartsAtZeroAndPersistsAcrossInstances() {
        let suite = makeSyncSuite()
        XCTAssertEqual(WatchLifetimeCounter(suiteName: suite).count, 0)
        WatchLifetimeCounter(suiteName: suite).increment()
        XCTAssertEqual(WatchLifetimeCounter(suiteName: suite).count, 1)
    }

    func testIncrementThenDecrementReturnsToZero() {
        let counter = WatchLifetimeCounter(suiteName: makeSyncSuite())
        counter.increment()
        counter.increment()
        counter.decrement()
        XCTAssertEqual(counter.count, 1)
    }

    func testNeverGoesBelowZero() {
        let counter = WatchLifetimeCounter(suiteName: makeSyncSuite())
        counter.decrement()
        XCTAssertEqual(counter.count, 0)
        counter.increment()
        counter.decrement()
        counter.decrement()
        XCTAssertEqual(counter.count, 0)
    }
}

final class PhoneStateContextTests: XCTestCase {
    func testRoundTripsThroughAPropertyListOnlyDictionary() throws {
        let context = PhoneStateContext(proUnlocked: true, completedMatchCount: 3)
        let dictionary = context.applicationContext
        XCTAssertEqual(Set(dictionary.keys), ["proUnlocked", "completedMatchCount"])
        // WatchConnectivity only accepts property-list values.
        XCTAssertTrue(PropertyListSerialization.propertyList(dictionary, isValidFor: .binary))
        XCTAssertEqual(PhoneStateContext(applicationContext: dictionary), context)
        // And through a real serialisation, as the system does.
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
        let decoded = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(PhoneStateContext(applicationContext: decoded), context)
    }

    func testAnIncompleteOrWrongTypedDictionaryIsIgnored() {
        XCTAssertNil(PhoneStateContext(applicationContext: [:]))
        XCTAssertNil(PhoneStateContext(applicationContext: ["proUnlocked": true]))
        XCTAssertNil(PhoneStateContext(applicationContext: ["proUnlocked": "yes", "completedMatchCount": 1]))
    }

    func testANegativeCountIsClampedToZero() {
        XCTAssertEqual(PhoneStateContext(applicationContext: ["proUnlocked": false, "completedMatchCount": -4])?.completedMatchCount, 0)
    }
}

final class ProEntitlementRuleTests: XCTestCase {
    private let pro = ProEntitlementRule.productID

    func testProductIDIsTheSharedOne() {
        XCTAssertEqual(ProEntitlementRule.productID, "com.delonsampaio.ServerTwo.pro")
    }

    func testOnlyAnUnrevokedProEntitlementCounts() {
        XCTAssertFalse(ProEntitlementRule.isPro(from: []))
        XCTAssertTrue(ProEntitlementRule.isPro(from: [.init(productID: pro, revocationDate: nil)]))
        XCTAssertFalse(ProEntitlementRule.isPro(from: [.init(productID: pro, revocationDate: Date())]))
        XCTAssertFalse(ProEntitlementRule.isPro(from: [.init(productID: "com.example.other", revocationDate: nil)]))
        XCTAssertTrue(ProEntitlementRule.isPro(from: [
            .init(productID: pro, revocationDate: Date()), .init(productID: pro, revocationDate: nil)
        ]), "a still-valid second copy keeps Pro")
    }
}

final class WatchEntitlementCacheTests: XCTestCase {
    func testStartsLockedAndEmpty() {
        let cache = WatchEntitlementCache(suiteName: makeSyncSuite())
        XCTAssertFalse(cache.phoneProUnlocked)
        XCTAssertEqual(cache.phoneCompletedMatchCount, 0)
    }

    func testAppliesAndPersistsThePhonesState() {
        let suite = makeSyncSuite()
        WatchEntitlementCache(suiteName: suite).apply(PhoneStateContext(proUnlocked: true, completedMatchCount: 2))
        let reloaded = WatchEntitlementCache(suiteName: suite)
        XCTAssertTrue(reloaded.phoneProUnlocked)
        XCTAssertEqual(reloaded.phoneCompletedMatchCount, 2)
    }
}

private struct FakeEntitlements: WatchEntitlementReading {
    let pro: Bool
    func isProEntitled() async -> Bool { pro }
}

@MainActor
final class WatchAccessTests: XCTestCase {
    private func makeAccess(storeKitPro: Bool = false) -> (WatchAccess, WatchLifetimeCounter) {
        let suite = makeSyncSuite()
        let counter = WatchLifetimeCounter(suiteName: suite)
        return (WatchAccess(
            counter: counter, cache: WatchEntitlementCache(suiteName: suite), entitlements: FakeEntitlements(pro: storeKitPro)
        ), counter)
    }

    func testAFreshFreeWatchMayStartOneMatch() {
        let (access, counter) = makeAccess()
        XCTAssertTrue(access.canStartMatch)
        counter.increment()
        XCTAssertFalse(access.canStartMatch)
    }

    func testThePhonesCountSharesTheBudget() {
        let (access, _) = makeAccess()
        access.apply(PhoneStateContext(proUnlocked: false, completedMatchCount: 1))
        XCTAssertFalse(access.canStartMatch, "phone count 1, watch 0")
        XCTAssertEqual(access.effectiveCompletedCount, 1)
    }

    func testProFromThePhoneUnlocks() {
        let (access, counter) = makeAccess()
        counter.increment()
        XCTAssertFalse(access.canStartMatch)
        access.apply(PhoneStateContext(proUnlocked: true, completedMatchCount: 1))
        XCTAssertTrue(access.isPro)
        XCTAssertTrue(access.canStartMatch)
    }

    func testProFromStoreKitUnlocks() async {
        let (access, counter) = makeAccess(storeKitPro: true)
        counter.increment()
        XCTAssertFalse(access.canStartMatch, "not read yet")
        await access.refreshEntitlements()
        XCTAssertTrue(access.isPro)
        XCTAssertTrue(access.canStartMatch)
    }

    func testAPhonePushOfFalseDoesNotRevokeStoreKitPro() async {
        let (access, _) = makeAccess(storeKitPro: true)
        await access.refreshEntitlements()
        access.apply(PhoneStateContext(proUnlocked: false, completedMatchCount: 0))
        XCTAssertTrue(access.isPro)
    }

    func testAPhonePushOfFalseRelocksAFormerPhoneUnlockWhenStoreKitIsNotPro() {
        let (access, counter) = makeAccess()
        counter.increment()
        access.apply(PhoneStateContext(proUnlocked: true, completedMatchCount: 1))
        access.apply(PhoneStateContext(proUnlocked: false, completedMatchCount: 1))
        XCTAssertFalse(access.isPro)
        XCTAssertFalse(access.canStartMatch)
    }

    func testACachedPhoneProSurvivesAStoreKitFalseRefresh() async {
        let suite = makeSyncSuite()
        let counter = WatchLifetimeCounter(suiteName: suite)
        counter.increment()
        WatchEntitlementCache(suiteName: suite).apply(PhoneStateContext(proUnlocked: true, completedMatchCount: 1))
        let access = WatchAccess(
            counter: counter, cache: WatchEntitlementCache(suiteName: suite), entitlements: FakeEntitlements(pro: false)
        )
        await access.refreshEntitlements()  // StoreKit says not Pro
        XCTAssertTrue(access.isPro, "the cached phone flag still unlocks (until the phone pushes false)")
        XCTAssertTrue(access.canStartMatch)
    }

    func testTheCachedPhoneStateSurvivesARelaunch() {
        let suite = makeSyncSuite()
        let first = WatchAccess(
            counter: WatchLifetimeCounter(suiteName: suite), cache: WatchEntitlementCache(suiteName: suite),
            entitlements: FakeEntitlements(pro: false)
        )
        first.apply(PhoneStateContext(proUnlocked: true, completedMatchCount: 4))
        let second = WatchAccess(
            counter: WatchLifetimeCounter(suiteName: suite), cache: WatchEntitlementCache(suiteName: suite),
            entitlements: FakeEntitlements(pro: false)
        )
        XCTAssertTrue(second.isPro, "buying Pro on the phone unlocks the watch even offline from Apple")
        XCTAssertEqual(second.effectiveCompletedCount, 4)
    }
}

@MainActor
final class PhoneStatePublisherTests: XCTestCase {
    private final class FakePusher: PhoneStatePushing {
        private let lock = OSAllocatedUnfairLock<[PhoneStateContext]>(initialState: [])
        func push(_ context: PhoneStateContext) { lock.withLock { $0.append(context) } }
        var contexts: [PhoneStateContext] { lock.withLock { $0 } }
    }

    func testPublishPushesTheCurrentStateEveryTime() {
        var isPro = false
        var count = 0
        let pusher = FakePusher()
        let publisher = PhoneStatePublisher(pusher: pusher, isPro: { isPro }, completedMatchCount: { count })

        publisher.publish()  // activation
        isPro = true
        publisher.publish()  // entitlement change
        count = 1
        publisher.publish()  // a match was saved

        XCTAssertEqual(pusher.contexts, [
            PhoneStateContext(proUnlocked: false, completedMatchCount: 0),
            PhoneStateContext(proUnlocked: true, completedMatchCount: 0),
            PhoneStateContext(proUnlocked: true, completedMatchCount: 1),
        ])
    }
}
