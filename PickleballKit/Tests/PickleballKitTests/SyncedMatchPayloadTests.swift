import XCTest
import SwiftData
@testable import PickleballKit

@MainActor
final class SyncedMatchPayloadTests: XCTestCase {
    func testRoundTripKeepsEveryField() throws {
        let payload = SyncedMatchPayload(
            id: UUID(), startedAt: SyncFixtures.t0, completedAt: SyncFixtures.t0.addingTimeInterval(1800.25),
            matchFormatRawValue: 3, configurationData: Data([1, 2, 3]), winningTeamRawValue: "teamA",
            teamAName: "Ann & Bo", teamBName: "Team B",
            games: [SyncFixtures.game(1, 11, 9, completedAt: SyncFixtures.t0.addingTimeInterval(5.5))]
        )
        let decoded = try SyncedMatchPayload.decode(from: try payload.encoded())
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.schemaVersion, SyncedMatchPayload.currentSchemaVersion)
        XCTAssertEqual(SyncedMatchPayload.currentSchemaVersion, 1)
    }

    func testEncodingIsStableAndDatesAreNumbers() throws {
        let payload = SyncFixtures.payload()
        XCTAssertEqual(try payload.encoded(), try payload.encoded())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try payload.encoded()) as? [String: Any])
        XCTAssertTrue(object["startedAt"] is NSNumber, "dates travel as numbers, not strings")
        XCTAssertTrue(object["completedAt"] is NSNumber)
    }

    func testBuilderFromARealSavedMatchCarriesGamesPointsAndNames() throws {
        let context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        let repository = MatchRepository(modelContext: context, seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite()))
        let id = UUID()
        let record = try SyncFixtures.saveRealMatch(repository, winner: .teamB, id: id)

        let payload = SyncedMatchPayload(record: record)

        XCTAssertEqual(payload.id, id)
        XCTAssertEqual(payload.winningTeamRawValue, Team.teamB.rawValue)
        XCTAssertEqual(payload.teamAName, "Team A")
        XCTAssertEqual(payload.games.count, 1)
        let game = try XCTUnwrap(payload.games.first)
        XCTAssertEqual(game.number, 1)
        XCTAssertGreaterThan(game.teamBFinalScore, game.teamAFinalScore)
        XCTAssertEqual(game.points.map(\.sequenceNumber), Array(1...game.points.count))
        XCTAssertEqual(game.points.last?.teamBScoreAfter, game.teamBFinalScore)
        XCTAssertNotNil(game.completedAt)
        // And what it builds is something the phone accepts.
        XCTAssertEqual(
            try MatchRepository(
                modelContext: ModelContext(try PersistenceContainer.makeInMemoryContainer()),
                seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite())
            ).importSyncedMatch(payload),
            .imported
        )
    }

    func testMessageUserInfoUsesTheAgreedKeys() throws {
        let id = UUID()
        let message = SyncedMatchMessage(matchID: id, payload: Data([9]))
        XCTAssertEqual(message.userInfo["matchID"] as? String, id.uuidString)
        XCTAssertEqual(message.userInfo["schema"] as? Int, 1)
        XCTAssertEqual(message.userInfo["payload"] as? Data, Data([9]))
        XCTAssertEqual(SyncedMatchWire.matchID(in: message.userInfo), id)
        XCTAssertEqual(SyncedMatchWire.acknowledgementUserInfo(for: id)["syncedMatchID"] as? String, id.uuidString)
        XCTAssertEqual(SyncedMatchWire.acknowledgedMatchID(in: SyncedMatchWire.acknowledgementUserInfo(for: id)), id)
    }

    func testIncomingParsesAValidTransfer() throws {
        let payload = SyncFixtures.payload()
        let message = SyncedMatchMessage(matchID: payload.id, payload: try payload.encoded())
        let incoming = try XCTUnwrap(IncomingSyncedMatch(userInfo: message.userInfo))
        XCTAssertEqual(incoming.matchID, payload.id)
        XCTAssertEqual(incoming.schema, 1)
        XCTAssertEqual(incoming.payload, payload)
    }

    func testIncomingKeepsTheIDWhenThePayloadIsGarbage() throws {
        let id = UUID()
        let incoming = try XCTUnwrap(IncomingSyncedMatch(userInfo: SyncedMatchMessage(matchID: id, payload: Data([0xFF])).userInfo))
        XCTAssertEqual(incoming.matchID, id)
        XCTAssertNil(incoming.payload)
    }

    func testIncomingDoesNotTryToDecodeANewerSchema() throws {
        let id = UUID()
        let incoming = try XCTUnwrap(IncomingSyncedMatch(
            userInfo: SyncedMatchMessage(matchID: id, schema: 2, payload: try SyncFixtures.payload(id: id).encoded()).userInfo
        ))
        XCTAssertEqual(incoming.schema, 2)
        XCTAssertNil(incoming.payload)
    }

    func testIncomingIgnoresADictionaryThatIsNotAMatchTransfer() {
        XCTAssertNil(IncomingSyncedMatch(userInfo: ["something": "else"]))
    }
}
