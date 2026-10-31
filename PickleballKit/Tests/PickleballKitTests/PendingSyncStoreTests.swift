import XCTest
@testable import PickleballKit

final class PendingSyncStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "PendingSyncStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testStartsEmpty() {
        XCTAssertEqual(PendingSyncStore(userDefaults: makeDefaults()).pendingMatchIDs, [])
    }

    func testAddKeepsOrderAndPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = UUID(), second = UUID()
        var store = PendingSyncStore(userDefaults: defaults)
        store.markPending(first)
        store.markPending(second)
        XCTAssertEqual(PendingSyncStore(userDefaults: defaults).pendingMatchIDs, [first, second])
        XCTAssertTrue(store.isPending(first))
    }

    func testMarkingTwiceDoesNotDuplicate() {
        var store = PendingSyncStore(userDefaults: makeDefaults())
        let id = UUID()
        store.markPending(id)
        store.markPending(id)
        XCTAssertEqual(store.pendingMatchIDs, [id])
    }

    func testConfirmRemovesOnlyThatMatch() {
        var store = PendingSyncStore(userDefaults: makeDefaults())
        let keep = UUID(), confirmed = UUID()
        store.markPending(keep)
        store.markPending(confirmed)
        store.confirmSynced(confirmed)
        XCTAssertEqual(store.pendingMatchIDs, [keep])
        XCTAssertFalse(store.isPending(confirmed))
        store.confirmSynced(UUID())  // unknown id is a no-op
        XCTAssertEqual(store.pendingMatchIDs, [keep])
    }
}
