import XCTest
@testable import PickleballKit

final class PendingSyncStoreTests: XCTestCase {
    /// A fresh defaults domain per test, returned as its name.
    private func makeDefaults() -> String {
        let suite = "PendingSyncStoreTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return suite
    }

    func testStartsEmpty() {
        XCTAssertEqual(PendingSyncStore(suiteName: makeDefaults()).pendingMatchIDs, [])
    }

    func testAddKeepsOrderAndPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = UUID(), second = UUID()
        let store = PendingSyncStore(suiteName: defaults)
        store.markPending(first)
        store.markPending(second)
        XCTAssertEqual(PendingSyncStore(suiteName: defaults).pendingMatchIDs, [first, second])
        XCTAssertTrue(store.isPending(first))
    }

    func testMarkingTwiceDoesNotDuplicate() {
        let store = PendingSyncStore(suiteName: makeDefaults())
        let id = UUID()
        store.markPending(id)
        store.markPending(id)
        XCTAssertEqual(store.pendingMatchIDs, [id])
    }

    func testConfirmRemovesOnlyThatMatch() {
        let store = PendingSyncStore(suiteName: makeDefaults())
        let keep = UUID(), confirmed = UUID()
        store.markPending(keep)
        store.markPending(confirmed)
        store.confirmSynced(confirmed)
        XCTAssertEqual(store.pendingMatchIDs, [keep])
        XCTAssertFalse(store.isPending(confirmed))
        store.confirmSynced(UUID())  // unknown id is a no-op
        XCTAssertEqual(store.pendingMatchIDs, [keep])
    }

    /// Sub-project B adds a second user (the WatchConnectivity delegate), so a
    /// read-modify-write from two threads must not lose an id.
    func testConcurrentMarksLoseNothing() {
        let store = PendingSyncStore(suiteName: makeDefaults())
        let ids = (0..<200).map { _ in UUID() }
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            store.markPending(ids[index])
        }
        XCTAssertEqual(Set(store.pendingMatchIDs), Set(ids))
        XCTAssertEqual(store.pendingMatchIDs.count, ids.count)
    }
}
