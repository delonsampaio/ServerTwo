import XCTest
import SwiftData
@testable import PickleballKit

@MainActor
final class WatchMatchReceiverTests: XCTestCase {
    private var context: ModelContext!
    private var repository: MatchRepository!
    private var acknowledger: FakeAcknowledger!
    private var receiver: WatchMatchReceiver!
    private var importedCounts: [Int] = []

    override func setUp() async throws {
        context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        repository = MatchRepository(modelContext: context, seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite()))
        acknowledger = FakeAcknowledger()
        importedCounts = []
        receiver = WatchMatchReceiver(repository: repository) { [unowned self] in self.importedCounts.append($0) }
    }

    private func incoming(_ payload: SyncedMatchPayload) throws -> IncomingSyncedMatch {
        try XCTUnwrap(IncomingSyncedMatch(userInfo: SyncedMatchMessage(matchID: payload.id, payload: try payload.encoded()).userInfo))
    }

    func testAValidMatchIsImportedAcknowledgedAndCountedOnceWithTheCountBeforeTheInsert() throws {
        try SyncFixtures.saveRealMatch(repository)  // one match already in history
        let payload = SyncFixtures.payload()

        XCTAssertEqual(receiver.receive(try incoming(payload), acknowledger: acknowledger), .imported)

        XCTAssertEqual(acknowledger.acknowledged, [payload.id])
        XCTAssertEqual(importedCounts, [1])
        XCTAssertEqual(try repository.fetchMatchHistory().count, 2)
    }

    func testADuplicateIsAcknowledgedButNeverCounted() throws {
        let payload = SyncFixtures.payload()
        receiver.receive(try incoming(payload), acknowledger: acknowledger)
        XCTAssertEqual(receiver.receive(try incoming(payload), acknowledger: acknowledger), .duplicate)
        XCTAssertEqual(acknowledger.acknowledged, [payload.id, payload.id])
        XCTAssertEqual(importedCounts.count, 1)
    }

    func testANewerSchemaIsNeitherAcknowledgedNorCounted() throws {
        let id = UUID()
        let newer = try XCTUnwrap(IncomingSyncedMatch(
            userInfo: SyncedMatchMessage(matchID: id, schema: 2, payload: Data([1])).userInfo
        ))
        XCTAssertEqual(receiver.receive(newer, acknowledger: acknowledger), .unsupportedNewerSchema)
        XCTAssertTrue(acknowledger.acknowledged.isEmpty)
        XCTAssertTrue(importedCounts.isEmpty)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
    }

    func testANewerSchemaInsideThePayloadIsNotAcknowledgedEither() throws {
        var payload = SyncFixtures.payload()
        payload.schemaVersion = 2
        XCTAssertEqual(receiver.receive(try incoming(payload), acknowledger: acknowledger), .unsupportedNewerSchema)
        XCTAssertTrue(acknowledger.acknowledged.isEmpty)
    }

    func testAnUndecodablePayloadIsAcknowledgedSoItDoesNotLoopForever() throws {
        let id = UUID()
        let garbage = try XCTUnwrap(IncomingSyncedMatch(userInfo: SyncedMatchMessage(matchID: id, payload: Data([0xFF])).userInfo))
        XCTAssertEqual(receiver.receive(garbage, acknowledger: acknowledger), .rejected(.undecodablePayload))
        XCTAssertEqual(acknowledger.acknowledged, [id])
        XCTAssertTrue(importedCounts.isEmpty)
    }

    func testAnUndecodablePayloadWithNoIDCannotBeAcknowledged() {
        let nothing = IncomingSyncedMatch(matchID: nil, schema: 1, payload: nil)
        XCTAssertEqual(receiver.receive(nothing, acknowledger: acknowledger), .rejected(.undecodablePayload))
        XCTAssertTrue(acknowledger.acknowledged.isEmpty)
    }

    func testAnInvalidMatchIsAcknowledgedAndNotCounted() throws {
        var payload = SyncFixtures.payload()
        payload.winningTeamRawValue = Team.teamB.rawValue
        XCTAssertEqual(receiver.receive(try incoming(payload), acknowledger: acknowledger), .rejected(.winnerMismatch))
        XCTAssertEqual(acknowledger.acknowledged, [payload.id])
        XCTAssertTrue(importedCounts.isEmpty)
    }

    func testALabelThatDisagreesWithThePayloadIsRejectedAndTheLabelAcknowledged() throws {
        let payload = SyncFixtures.payload()
        let label = UUID()
        let mismatched = IncomingSyncedMatch(matchID: label, schema: 1, payload: payload)
        XCTAssertEqual(receiver.receive(mismatched, acknowledger: acknowledger), .rejected(.idMismatch))
        XCTAssertEqual(acknowledger.acknowledged, [label])
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
    }

    func testADeletedThenResentMatchIsAcknowledgedButNotCountedOrRestored() throws {
        let payload = SyncFixtures.payload()
        receiver.receive(try incoming(payload), acknowledger: acknowledger)
        try repository.deleteMatch(try XCTUnwrap(try repository.fetchMatchRecord(id: payload.id)))

        XCTAssertEqual(receiver.receive(try incoming(payload), acknowledger: acknowledger), .duplicate)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
        XCTAssertEqual(importedCounts.count, 1)
    }
}
