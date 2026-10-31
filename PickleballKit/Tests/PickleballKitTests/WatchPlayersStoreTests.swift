import XCTest
@testable import PickleballKit

final class WatchPlayersStoreTests: XCTestCase {
    private func makeStore(capacity: Int = WatchPlayersStore.defaultCapacity) -> (WatchPlayersStore, String) {
        let suite = "WatchPlayersStoreTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (WatchPlayersStore(suiteName: suite, capacity: capacity), suite)
    }

    private let mike = SyncedPlayerRef(savedPlayerID: UUID(), name: "Mike")
    private let sarah = SyncedPlayerRef(name: "Sarah")

    func testStartsEmpty() {
        let (store, _) = makeStore()
        XCTAssertNil(store.currentMatchPlayers)
        XCTAssertNil(store.players(forSavedMatch: UUID()))
    }

    func testCurrentMatchPlayersPersistAndClear() {
        let (store, suite) = makeStore()
        let players = WatchMatchPlayers(teamA: [mike], teamB: [sarah])
        store.setCurrentMatchPlayers(players)
        XCTAssertEqual(WatchPlayersStore(suiteName: suite).currentMatchPlayers, players)
        store.clearCurrentMatchPlayers()
        XCTAssertNil(store.currentMatchPlayers)
        store.setCurrentMatchPlayers(players)
        store.setCurrentMatchPlayers(.empty)
        XCTAssertNil(store.currentMatchPlayers, "an empty value clears")
    }

    func testSavedMatchEntriesAreKeptPerMatchAndRemovedIndividually() {
        let (store, suite) = makeStore()
        let first = UUID(), second = UUID()
        store.setPlayers(WatchMatchPlayers(teamA: [mike], teamB: []), forSavedMatch: first)
        store.setPlayers(WatchMatchPlayers(teamA: [], teamB: [sarah]), forSavedMatch: second)
        let reloaded = WatchPlayersStore(suiteName: suite)
        XCTAssertEqual(reloaded.players(forSavedMatch: first)?.teamA, [mike])
        XCTAssertEqual(reloaded.players(forSavedMatch: second)?.teamB, [sarah])
        store.removePlayers(forSavedMatch: first)
        XCTAssertNil(store.players(forSavedMatch: first))
        XCTAssertNotNil(store.players(forSavedMatch: second))
    }

    func testSettingEmptyPlayersRemovesTheEntryAndRewritingReplacesIt() {
        let (store, _) = makeStore()
        let id = UUID()
        store.setPlayers(WatchMatchPlayers(teamA: [mike]), forSavedMatch: id)
        store.setPlayers(WatchMatchPlayers(teamA: [sarah]), forSavedMatch: id)
        XCTAssertEqual(store.players(forSavedMatch: id)?.teamA, [sarah])
        store.setPlayers(.empty, forSavedMatch: id)
        XCTAssertNil(store.players(forSavedMatch: id))
    }

    func testTheOldestSavedEntriesGoFirstWhenOverCapacity() {
        let (store, _) = makeStore(capacity: 3)
        let ids = (0..<5).map { _ in UUID() }
        for id in ids { store.setPlayers(WatchMatchPlayers(teamA: [mike]), forSavedMatch: id) }
        XCTAssertNil(store.players(forSavedMatch: ids[0]))
        XCTAssertNil(store.players(forSavedMatch: ids[1]))
        XCTAssertNotNil(store.players(forSavedMatch: ids[2]))
        XCTAssertNotNil(store.players(forSavedMatch: ids[4]))
    }

    func testPruneDropsEntriesForMatchesThatNoLongerExist() {
        let (store, _) = makeStore()
        let keep = UUID(), gone = UUID()
        store.setPlayers(WatchMatchPlayers(teamA: [mike]), forSavedMatch: keep)
        store.setPlayers(WatchMatchPlayers(teamA: [sarah]), forSavedMatch: gone)
        store.prune(keepingSavedMatches: [keep])
        XCTAssertNotNil(store.players(forSavedMatch: keep))
        XCTAssertNil(store.players(forSavedMatch: gone))
    }

    func testCorruptDataReadsAsEmpty() {
        let (store, suite) = makeStore()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(Data([0xFF, 0x00]), forKey: WatchPlayersStore.currentKey)
        defaults.set(Data([0xFF, 0x00]), forKey: WatchPlayersStore.savedKey)
        XCTAssertNil(store.currentMatchPlayers)
        XCTAssertNil(store.players(forSavedMatch: UUID()))
        store.setPlayers(WatchMatchPlayers(teamA: [mike]), forSavedMatch: UUID())  // and it recovers
    }

    func testMatchPlayersSlicingAndNaming() {
        let players = WatchMatchPlayers(
            teamA: [mike, SyncedPlayerRef(name: "  "), sarah, SyncedPlayerRef(name: "Third")],
            teamB: []
        )
        XCTAssertEqual(players.sliced(for: .doubles).teamA, [mike, sarah])
        XCTAssertEqual(players.sliced(for: .singles).teamA, [mike])
        XCTAssertEqual(players.sliced(for: .doubles).teamName(for: .teamA), "Mike & Sarah")
        XCTAssertEqual(players.teamName(for: .teamB), "Team B")
        let long = WatchMatchPlayers(teamA: [SyncedPlayerRef(name: String(repeating: "x", count: 70))])
        XCTAssertEqual(long.sliced(for: .doubles).teamA.first?.name.count, 64)
    }
}
