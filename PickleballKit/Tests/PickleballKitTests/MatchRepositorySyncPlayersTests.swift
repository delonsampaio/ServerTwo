import XCTest
import SwiftData
@testable import PickleballKit

/// The player linking in `importSyncedMatch` and the payload's player fields.
@MainActor
final class MatchRepositorySyncPlayersTests: XCTestCase {
    private var context: ModelContext!
    private var repository: MatchRepository!
    private var seen: SeenMatchIDStore!

    override func setUp() async throws {
        context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        seen = SeenMatchIDStore(suiteName: makeSyncSuite())
        repository = MatchRepository(modelContext: context, seenMatchIDs: seen)
    }

    private func ref(_ name: String, _ id: UUID? = nil) -> SyncedPlayerRef {
        SyncedPlayerRef(savedPlayerID: id, name: name)
    }

    private func imported(_ payload: SyncedMatchPayload) throws -> (a: TeamSide, b: TeamSide) {
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
        let sides = try XCTUnwrap(try repository.fetchMatchRecord(id: payload.id)?.teamSides)
        return (try XCTUnwrap(sides.first { $0.team == .teamA }), try XCTUnwrap(sides.first { $0.team == .teamB }))
    }

    private func savedNames() throws -> [String] {
        try repository.fetchAllSavedPlayers().map(\.name).sorted()
    }

    private let singles = GameConfiguration(playMode: .singles, scoringFormat: .sideOut)

    // MARK: Payload

    func testPlayerFieldsRoundTripAndOldPayloadsStillDecode() throws {
        let id = UUID()
        let payload = SyncFixtures.payload(
            teamAName: "Ann & Bo", teamBName: "Cy",
            teamAPlayers: [ref("Ann", id), ref("Bo")], teamBPlayers: [ref("Cy")]
        )
        XCTAssertEqual(try SyncedMatchPayload.decode(from: try payload.encoded()), payload)
        XCTAssertEqual(try payload.encoded(), try payload.encoded(), "stable bytes")
        XCTAssertEqual(payload.schemaVersion, 1)

        // A payload from a Watch that predates the fields (no keys at all).
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try payload.encoded()) as? [String: Any])
        object.removeValue(forKey: "teamAPlayers")
        object.removeValue(forKey: "teamBPlayers")
        let old = try SyncedMatchPayload.decode(from: try JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.teamAPlayers)
        XCTAssertNil(old.teamBPlayers)
        XCTAssertEqual(old.teamAName, "Ann & Bo")
    }

    func testNoPlayersMeansNoKeysInTheEncodedPayload() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try SyncFixtures.payload().encoded()) as? [String: Any])
        XCTAssertNil(object["teamAPlayers"])
        XCTAssertNil(object["teamBPlayers"])
    }

    func testBuilderPutsTheEntriesInAndKeepsTheNamesFilled() throws {
        let record = try SyncFixtures.saveRealMatch(repository)
        let players = WatchMatchPlayers(teamA: [ref("Ann", UUID()), ref("Bo")], teamB: [])
        let payload = SyncedMatchPayload(record: record, players: players)
        XCTAssertEqual(payload.teamAPlayers, players.teamA)
        XCTAssertNil(payload.teamBPlayers, "an empty side sends no array")
        XCTAssertEqual(payload.teamAName, "Team A", "names always come from the record")
        XCTAssertEqual(payload.teamBName, "Team B")
        XCTAssertNil(SyncedMatchPayload(record: record).teamAPlayers)
    }

    // MARK: Linking

    func testAKnownIDLinksThatPlayer() throws {
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let payload = SyncFixtures.payload(teamAName: "Mike", teamAPlayers: [ref("Mike", mike.id)], configuration: singles)
        let sides = try imported(payload)
        XCTAssertEqual(sides.a.players?.map(\.id), [mike.id])
        XCTAssertEqual(sides.a.displayName, "Mike")
        XCTAssertEqual(try savedNames(), ["Mike"])
    }

    func testAKnownIDWithAChangedNameIsTrustedAndTheSideTakesTheCurrentName() throws {
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let other = try XCTUnwrap(repository.upsertSavedPlayer(name: "Michael"))
        try repository.renameSavedPlayer(mike, to: "Mikey")
        // The Watch still knows "Mike", and another player now has an
        // unrelated name: the id decides, not the old name.
        let payload = SyncFixtures.payload(teamAName: "Mike", teamAPlayers: [ref("Mike", mike.id)], configuration: singles)
        let sides = try imported(payload)
        XCTAssertEqual(sides.a.players?.map(\.id), [mike.id])
        XCTAssertEqual(sides.a.displayName, "Mikey", "recomputed from the resolved player")
        XCTAssertEqual(try savedNames(), ["Michael", "Mikey"])
        _ = other
    }

    func testAnUnknownIDFallsBackToTheNameMatch() throws {
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let sides = try imported(SyncFixtures.payload(
            teamAName: "Mike", teamAPlayers: [ref("mike", UUID())], configuration: singles
        ))
        XCTAssertEqual(sides.a.players?.map(\.id), [mike.id])
        XCTAssertEqual(sides.a.displayName, "Mike", "the existing player's casing")
        XCTAssertEqual(try savedNames(), ["Mike"])
    }

    func testAnUnknownIDWithANewNameCreatesThePlayer() throws {
        let sides = try imported(SyncFixtures.payload(
            teamAName: "Zoe", teamAPlayers: [ref("Zoe", UUID())], configuration: singles
        ))
        XCTAssertEqual(try savedNames(), ["Zoe"])
        XCTAssertEqual(sides.a.players?.map(\.name), ["Zoe"])
    }

    func testATypedNameEqualToAnExistingPlayerInAnotherCaseLinksIt() throws {
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let sides = try imported(SyncFixtures.payload(teamAName: "mIKE", teamAPlayers: [ref("mIKE")], configuration: singles))
        XCTAssertEqual(sides.a.players?.map(\.id), [mike.id])
        XCTAssertEqual(try savedNames(), ["Mike"])
    }

    func testNewNamesCreateOnePlayerEachEvenWhenTheSameNameIsInTwoSlots() throws {
        let sides = try imported(SyncFixtures.payload(
            teamAName: "Ann & Bo", teamBName: "Bo & Cy",
            teamAPlayers: [ref("Ann"), ref("Bo")], teamBPlayers: [ref("bo"), ref("Cy")]
        ))
        XCTAssertEqual(try savedNames(), ["Ann", "Bo", "Cy"], "one Bo, not two")
        // Bo stays on side A; the repeat is dropped from side B.
        XCTAssertEqual(sides.a.players?.map(\.name).sorted(), ["Ann", "Bo"])
        XCTAssertEqual(sides.b.players?.map(\.name), ["Cy"])
        XCTAssertEqual(sides.a.displayName, "Ann & Bo")
        XCTAssertEqual(sides.b.displayName, "Cy")
    }

    func testTheSamePlayerOnBothSidesIsDroppedFromTheSecond() throws {
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let sides = try imported(SyncFixtures.payload(
            teamAName: "Mike", teamBName: "Mike",
            teamAPlayers: [ref("Mike", mike.id)], teamBPlayers: [ref("Mike", mike.id)], configuration: singles
        ))
        XCTAssertEqual(sides.a.players?.map(\.id), [mike.id])
        XCTAssertTrue((sides.b.players ?? []).isEmpty)
        XCTAssertEqual(sides.b.displayName, "Mike", "kept the payload's name, nobody linked")
    }

    func testThePlayerIsNeverLinkedTwiceOnOneSide() throws {
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let sides = try imported(SyncFixtures.payload(
            teamAName: "Mike & Mike", teamAPlayers: [ref("Mike", mike.id), ref("MIKE")]
        ))
        XCTAssertEqual(sides.a.players?.map(\.id), [mike.id])
        XCTAssertEqual(sides.a.displayName, "Mike")
    }

    func testTwoSavedPlayersSharingANameStayApartWhenPickedByID() throws {
        let one = SavedPlayer(name: "Mike"), two = SavedPlayer(name: "Mike")
        context.insert(one)
        context.insert(two)
        try context.save()
        let sides = try imported(SyncFixtures.payload(
            teamAName: "Mike", teamBName: "Mike",
            teamAPlayers: [ref("Mike", one.id)], teamBPlayers: [ref("Mike", two.id)], configuration: singles
        ))
        XCTAssertEqual(sides.a.players?.map(\.id), [one.id])
        XCTAssertEqual(sides.b.players?.map(\.id), [two.id])
    }

    // MARK: Validation

    func testBlankOverLongAndControlCharacterEntries() throws {
        let tooLong = String(repeating: "x", count: 65)
        let sides = try imported(SyncFixtures.payload(
            teamAName: "Ann", teamBName: "Team B",
            teamAPlayers: [ref("  "), ref(tooLong), ref(" Ann\n ")],
            teamBPlayers: [ref("\t"), ref(tooLong)]
        ))
        XCTAssertEqual(try savedNames(), ["Ann"])
        XCTAssertEqual(sides.a.players?.map(\.name), ["Ann"])
        XCTAssertTrue((sides.b.players ?? []).isEmpty)
        XCTAssertEqual(sides.b.displayName, "Team B", "the match still imports with its name string")
    }

    func testAnExactly64CharacterNameIsKept() throws {
        let name = String(repeating: "x", count: 64)
        _ = try imported(SyncFixtures.payload(teamAName: name, teamAPlayers: [ref(name)], configuration: singles))
        XCTAssertEqual(try savedNames(), [name])
    }

    func testTheCapIsOnePerSideForSinglesAndTwoForDoubles() throws {
        let singlesSides = try imported(SyncFixtures.payload(
            teamAPlayers: [ref("A1"), ref("A2")], teamBPlayers: [ref("B1"), ref("B2")], configuration: singles
        ))
        XCTAssertEqual(singlesSides.a.players?.map(\.name), ["A1"])
        XCTAssertEqual(singlesSides.b.players?.map(\.name), ["B1"])

        let doublesSides = try imported(SyncFixtures.payload(
            teamAPlayers: [ref("D1"), ref("D2"), ref("D3")], teamBPlayers: [ref("E1"), ref("E2"), ref("E3")]
        ))
        XCTAssertEqual(doublesSides.a.players?.map(\.name).sorted(), ["D1", "D2"])
        XCTAssertEqual(doublesSides.b.players?.map(\.name).sorted(), ["E1", "E2"])
        XCTAssertEqual(try savedNames(), ["A1", "B1", "D1", "D2", "E1", "E2"], "dropped entries create nothing")
    }

    // MARK: Old payloads, idempotence, atomicity

    func testAnOldPayloadWithoutPlayerKeysImportsNamesOnly() throws {
        let sides = try imported(SyncFixtures.payload(teamAName: "Ann & Bo", teamBName: "Cy"))
        XCTAssertEqual(sides.a.displayName, "Ann & Bo")
        XCTAssertEqual(sides.b.displayName, "Cy")
        XCTAssertTrue((sides.a.players ?? []).isEmpty)
        XCTAssertTrue((sides.b.players ?? []).isEmpty)
        XCTAssertEqual(try savedNames(), [], "no saved players are created from names alone")
    }

    func testResendingTheSamePayloadIsADuplicateAndCreatesNothingMore() throws {
        let payload = SyncFixtures.payload(teamAName: "Ann", teamAPlayers: [ref("Ann")], configuration: singles)
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
        XCTAssertEqual(try repository.importSyncedMatch(payload), .duplicate)
        XCTAssertEqual(try savedNames(), ["Ann"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MatchRecord>()), 1)
    }

    func testAFailedSaveLeavesNoOrphanPlayerOrMatchAndARetrySucceeds() throws {
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let payload = SyncFixtures.payload(
            teamAName: "Mike & Zed", teamBName: "Amy",
            teamAPlayers: [ref("Mike", mike.id), ref("Zed")], teamBPlayers: [ref("Amy")]
        )
        struct Boom: Error {}
        XCTAssertThrowsError(try repository.importSyncedMatch(payload, beforeSave: { throw Boom() }))

        XCTAssertEqual(try savedNames(), ["Mike"], "no orphan Zed or Amy")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MatchRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TeamSide>()), 0)
        XCTAssertFalse(seen.contains(payload.id))
        XCTAssertTrue((mike.teamSides ?? []).isEmpty)

        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
        XCTAssertEqual(try savedNames(), ["Amy", "Mike", "Zed"])
    }

    func testMatchAndNewPlayersAreCommittedByOneSave() throws {
        // The new player must be unsaved until the single save: the seam runs
        // before it, and a fresh context on the same store sees nothing yet.
        let container = try PersistenceContainer.makeInMemoryContainer()
        let writer = MatchRepository(modelContext: ModelContext(container), seenMatchIDs: seen)
        let reader = ModelContext(container)
        let payload = SyncFixtures.payload(teamAName: "Zed", teamAPlayers: [ref("Zed")], configuration: singles)
        var playersVisibleBeforeSave = -1
        _ = try writer.importSyncedMatch(payload, beforeSave: {
            playersVisibleBeforeSave = try reader.fetchCount(FetchDescriptor<SavedPlayer>())
        })
        XCTAssertEqual(playersVisibleBeforeSave, 0)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<SavedPlayer>()), 1)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<MatchRecord>()), 1)
    }
}
