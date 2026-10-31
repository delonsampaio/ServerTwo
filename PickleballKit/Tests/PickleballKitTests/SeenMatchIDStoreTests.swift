import XCTest
@testable import PickleballKit

final class SeenMatchIDStoreTests: XCTestCase {
    func testRemembersIdsAcrossInstances() {
        let suite = makeSyncSuite()
        let id = UUID()
        SeenMatchIDStore(suiteName: suite).insert(id)
        XCTAssertTrue(SeenMatchIDStore(suiteName: suite).contains(id))
        XCTAssertFalse(SeenMatchIDStore(suiteName: suite).contains(UUID()))
    }

    func testInsertingTwiceKeepsOneEntry() {
        let store = SeenMatchIDStore(suiteName: makeSyncSuite())
        let id = UUID()
        store.insert(id)
        store.insert(id)
        XCTAssertEqual(store.ids, [id])
    }

    func testIsBoundedAndDropsTheOldestFirst() {
        let store = SeenMatchIDStore(suiteName: makeSyncSuite(), capacity: 3)
        let ids = (0..<5).map { _ in UUID() }
        ids.forEach { store.insert($0) }
        XCTAssertEqual(store.ids, Array(ids.suffix(3)))
        XCTAssertFalse(store.contains(ids[0]))
    }

    func testDefaultCapacityIs500() {
        XCTAssertEqual(SeenMatchIDStore.defaultCapacity, 500)
        let store = SeenMatchIDStore(suiteName: makeSyncSuite())
        store.insert(contentsOf: (0..<520).map { _ in UUID() })
        XCTAssertEqual(store.ids.count, 500)
    }
}
