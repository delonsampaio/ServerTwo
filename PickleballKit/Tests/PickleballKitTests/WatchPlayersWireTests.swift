import XCTest
import SwiftData
@testable import PickleballKit

final class WatchPlayersWireTests: XCTestCase {
    private func player(_ name: String, isMe: Bool = false) -> WatchPlayer {
        WatchPlayer(id: UUID(), name: name, isMe: isMe)
    }

    // MARK: Wire types

    func testWireTypesRoundTripThroughJSON() throws {
        let players = [player("Ann", isMe: true), player("Bo")]
        XCTAssertEqual(try JSONDecoder().decode([WatchPlayer].self, from: JSONEncoder().encode(players)), players)
        let refs = [SyncedPlayerRef(savedPlayerID: UUID(), name: "Ann"), SyncedPlayerRef(name: "Cy")]
        XCTAssertEqual(try JSONDecoder().decode([SyncedPlayerRef].self, from: JSONEncoder().encode(refs)), refs)
    }

    func testANilPlayerIDIsOmittedFromTheJSON() throws {
        let data = try JSONEncoder().encode(SyncedPlayerRef(name: "Cy"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["name"])
    }

    // MARK: PhoneStateContext.players

    func testPlayersRoundTripThroughAPropertyListDictionary() throws {
        let players = [player("Ann", isMe: true), player("Bo")]
        let context = PhoneStateContext(proUnlocked: true, completedMatchCount: 2, players: players)
        let dictionary = context.applicationContext
        XCTAssertEqual(Set(dictionary.keys), ["proUnlocked", "completedMatchCount", "players"])
        XCTAssertTrue(dictionary["players"] is Data)
        XCTAssertTrue(PropertyListSerialization.propertyList(dictionary, isValidFor: .binary))
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
        let decoded = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(PhoneStateContext(applicationContext: decoded), context)
    }

    func testTheOldTwoKeyDictionaryStillParsesWithNoPlayers() throws {
        let old: [String: Any] = ["proUnlocked": true, "completedMatchCount": 4]
        let context = try XCTUnwrap(PhoneStateContext(applicationContext: old))
        XCTAssertTrue(context.proUnlocked)
        XCTAssertEqual(context.completedMatchCount, 4)
        XCTAssertNil(context.players)
        // And a state without players still writes the old two keys only.
        XCTAssertEqual(Set(context.applicationContext.keys), ["proUnlocked", "completedMatchCount"])
    }

    func testAnEmptyListIsDifferentFromAnAbsentOne() throws {
        let empty = PhoneStateContext(proUnlocked: false, completedMatchCount: 0, players: [])
        XCTAssertEqual(PhoneStateContext(applicationContext: empty.applicationContext)?.players, [])
        XCTAssertNotEqual(empty, PhoneStateContext(proUnlocked: false, completedMatchCount: 0))
    }

    func testAnUndecodablePlayersEntryReadsAsNilButKeepsTheProState() throws {
        for bad: Any in [Data([1, 2, 3]), "not data", 7, Data("{\"a\":1}".utf8)] {
            let context = try XCTUnwrap(PhoneStateContext(
                applicationContext: ["proUnlocked": true, "completedMatchCount": 1, "players": bad]
            ))
            XCTAssertNil(context.players, "\(bad)")
            XCTAssertTrue(context.proUnlocked)
        }
    }

    func testMalformedPlayerEntriesAreDroppedAndTheRestKept() throws {
        let good = player("Ann")
        let goodJSON = try String(decoding: JSONEncoder().encode(good), as: UTF8.self)
        let json = "[\(goodJSON), {\"id\": \"nope\", \"name\": \"X\", \"isMe\": false}, {\"name\": 5}, 3]"
        let context = try XCTUnwrap(PhoneStateContext(applicationContext: [
            "proUnlocked": false, "completedMatchCount": 0, "players": Data(json.utf8)
        ]))
        XCTAssertEqual(context.players, [good])
    }

    // MARK: List cleaning

    func testNormalizedDropsBlanksTruncatesNamesAndCapsAtFifty() {
        let long = String(repeating: "x", count: 100)
        let cleaned = WatchPlayerList.normalized([player("  Ann  "), player("   "), player(long)])
        XCTAssertEqual(cleaned.map(\.name), ["Ann", String(repeating: "x", count: 64)])

        let many = (0..<80).map { player("P\($0)") }
        let capped = WatchPlayerList.normalized(many)
        XCTAssertEqual(capped.count, 50)
        XCTAssertEqual(capped.first?.name, "P0")
        XCTAssertEqual(capped.last?.name, "P49")
    }

    func testPlayerNameRules() {
        XCTAssertEqual(PlayerNameRules.stripped("  A\nB\u{7} "), "AB")
        XCTAssertNil(PlayerNameRules.truncated(" \n "))
        XCTAssertEqual(PlayerNameRules.truncated(String(repeating: "x", count: 63) + "  yy"), String(repeating: "x", count: 63))
        XCTAssertNil(PlayerNameRules.validated(String(repeating: "x", count: 65)))
        XCTAssertEqual(PlayerNameRules.validated(String(repeating: "x", count: 64))?.count, 64)
        XCTAssertNil(PlayerNameRules.validated("\n"))
    }

    // MARK: The phone's list

    @MainActor
    func testPhoneListPutsMeFirstThenRecentThenFrequentThenNameThenID() throws {
        let context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        let repository = MatchRepository(modelContext: context, seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite()))
        let me = SavedPlayer(name: "Zed", isMe: true)
        let recent = SavedPlayer(name: "Recent")
        let old = SavedPlayer(name: "Old")
        let beta = SavedPlayer(name: "beta")
        let alpha = SavedPlayer(name: "Alpha")
        // Two players with the same name: the id decides, and it is stable.
        let twinA = SavedPlayer(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, name: "Twin")
        let twinB = SavedPlayer(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, name: "Twin")
        [me, recent, old, beta, alpha, twinB, twinA].forEach(context.insert)
        try context.save()

        let t = SyncFixtures.t0
        try repository.saveCompletedMatch(
            try finishedMatch(), teamAName: "Old", teamBName: "x", startedAt: t, completedAt: t.addingTimeInterval(10),
            teamAPlayers: [old], teamBPlayers: []
        )
        try repository.saveCompletedMatch(
            try finishedMatch(), teamAName: "Recent", teamBName: "x", startedAt: t, completedAt: t.addingTimeInterval(500),
            teamAPlayers: [recent], teamBPlayers: []
        )

        let list = try repository.watchPlayerList()
        XCTAssertEqual(list.map(\.name), ["Zed", "Recent", "Old", "Alpha", "beta", "Twin", "Twin"])
        XCTAssertEqual(list.filter(\.isMe).count, 1)
        XCTAssertEqual(list.first?.isMe, true)
        XCTAssertEqual(list.suffix(2).map(\.id), [twinA.id, twinB.id])
        XCTAssertEqual(try repository.watchPlayerList(), list, "deterministic")
    }

    @MainActor
    func testPhoneListIsCappedAndNamesTruncated() throws {
        let context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        let repository = MatchRepository(modelContext: context, seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite()))
        for index in 0..<60 { context.insert(SavedPlayer(name: String(format: "P%02d", index))) }
        context.insert(SavedPlayer(name: String(repeating: "y", count: 90)))
        try context.save()
        let list = try repository.watchPlayerList()
        XCTAssertEqual(list.count, 50)
        XCTAssertTrue(list.allSatisfy { $0.name.count <= 64 })
    }

    @MainActor
    private func finishedMatch() throws -> PickleballMatch {
        let match = PickleballMatch(
            configuration: GameConfiguration(), matchFormat: .bestOfOne,
            firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil
        )
        playOutGame(match, winner: .teamA)
        return match
    }
}

@MainActor
final class WatchPlayerDirectoryTests: XCTestCase {
    private func makeDirectory(_ suite: String? = nil) -> (WatchPlayerDirectory, String) {
        let suiteName = suite ?? makeSyncSuite()
        return (WatchPlayerDirectory(suiteName: suiteName), suiteName)
    }

    private func state(_ players: [WatchPlayer]?) -> PhoneStateContext {
        PhoneStateContext(proUnlocked: false, completedMatchCount: 0, players: players)
    }

    func testStartsEmpty() {
        XCTAssertEqual(makeDirectory().0.options, [])
    }

    func testAPhoneListIsCachedCleanedAndSurvivesARelaunch() {
        let (directory, suite) = makeDirectory()
        let me = WatchPlayer(id: UUID(), name: "Delon", isMe: true)
        let long = WatchPlayer(id: UUID(), name: String(repeating: "x", count: 80))
        directory.apply(state([me, WatchPlayer(id: UUID(), name: "  "), long]))
        XCTAssertEqual(directory.options.map(\.entry.name), ["Delon", String(repeating: "x", count: 64)])
        XCTAssertEqual(directory.options.first?.isMe, true)
        XCTAssertEqual(directory.options.first?.entry.savedPlayerID, me.id)

        XCTAssertEqual(WatchPlayerDirectory(suiteName: suite).options, directory.options, "read from the cache")
    }

    func testTheCacheIsCappedAtFifty() {
        let (directory, _) = makeDirectory()
        directory.apply(state((0..<70).map { WatchPlayer(id: UUID(), name: "P\($0)") }))
        XCTAssertEqual(directory.options.count, 50)
    }

    func testAStateWithoutAListNeverOverwritesTheCache() {
        let (directory, suite) = makeDirectory()
        directory.apply(state([WatchPlayer(id: UUID(), name: "Ann")]))
        directory.apply(state(nil))
        XCTAssertEqual(directory.options.map(\.entry.name), ["Ann"])
        XCTAssertEqual(WatchPlayerDirectory(suiteName: suite).options.map(\.entry.name), ["Ann"])
    }

    func testAnExplicitEmptyListClearsTheCache() {
        let (directory, suite) = makeDirectory()
        directory.apply(state([WatchPlayer(id: UUID(), name: "Ann")]))
        directory.apply(state([]))
        XCTAssertEqual(directory.options, [])
        XCTAssertEqual(WatchPlayerDirectory(suiteName: suite).options, [])
    }

    func testATypedNameEqualToACachedPlayerLinksThatPlayer() throws {
        let (directory, _) = makeDirectory()
        let mike = WatchPlayer(id: UUID(), name: "Mike")
        directory.apply(state([mike]))
        XCTAssertEqual(directory.resolve(typedName: "  mIKE "), SyncedPlayerRef(savedPlayerID: mike.id, name: "Mike"))
        XCTAssertEqual(directory.resolve(typedName: "Sarah"), SyncedPlayerRef(name: "Sarah"))
        XCTAssertNil(directory.resolve(typedName: "   "))
    }

    func testATypedNameIsListedLocallyUntilThePhonesNextList() {
        let (directory, suite) = makeDirectory()
        let ann = WatchPlayer(id: UUID(), name: "Ann")
        directory.apply(state([ann]))
        directory.remember(SyncedPlayerRef(name: "Sarah"))
        XCTAssertEqual(directory.options.map(\.entry.name), ["Ann", "Sarah"])
        XCTAssertNil(directory.options.last?.entry.savedPlayerID)
        XCTAssertEqual(WatchPlayerDirectory(suiteName: suite).options.map(\.entry.name), ["Ann", "Sarah"])

        // A list without her (the phone has not got the match yet) replaces it.
        directory.apply(state([ann]))
        XCTAssertEqual(directory.options.map(\.entry.name), ["Ann"])
        // A list with her (as a real player) shows her once.
        directory.remember(SyncedPlayerRef(name: "Sarah"))
        directory.apply(state([ann, WatchPlayer(id: UUID(), name: "Sarah")]))
        XCTAssertEqual(directory.options.map(\.entry.name), ["Ann", "Sarah"])
        XCTAssertNotNil(directory.options.last?.entry.savedPlayerID)
    }

    func testRememberIgnoresLinkedPlayersAndKnownNames() {
        let (directory, _) = makeDirectory()
        let ann = WatchPlayer(id: UUID(), name: "Ann")
        directory.apply(state([ann]))
        directory.remember(SyncedPlayerRef(savedPlayerID: ann.id, name: "Ann"))
        directory.remember(SyncedPlayerRef(name: "ann"))
        directory.remember(SyncedPlayerRef(name: "Sarah"))
        directory.remember(SyncedPlayerRef(name: "SARAH"))
        XCTAssertEqual(directory.options.map(\.entry.name), ["Ann", "Sarah"])
    }
}
