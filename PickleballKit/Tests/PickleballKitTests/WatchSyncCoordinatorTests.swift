import XCTest
import SwiftData
@testable import PickleballKit

@MainActor
final class WatchSyncCoordinatorTests: XCTestCase {
    private var suite = ""
    private var repository: MatchRepository!
    private var pending: PendingSyncStore!
    private var transport: FakeWatchTransport!
    private var session: StandaloneMatchSession!
    private var coordinator: WatchSyncCoordinator!

    override func setUp() async throws {
        suite = makeSyncSuite()
        let context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        repository = MatchRepository(modelContext: context, seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite()))
        pending = PendingSyncStore(suiteName: suite)
        transport = FakeWatchTransport()
        session = StandaloneMatchSession(repository: repository, pendingSync: pending)
        coordinator = WatchSyncCoordinator(
            repository: repository, pendingSync: pending, transport: transport, session: session
        )
        coordinator.start()
    }

    /// A saved, pending match that is NOT the session's undoable one.
    private func queuedMatch() throws -> UUID {
        let record = try SyncFixtures.saveRealMatch(repository)
        pending.markPending(record.id)
        return record.id
    }

    /// Plays a whole best-of-1 on the session so the deciding point saves it.
    private func finishMatchOnSession() {
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        var taps = 0
        while !session.isMatchOver, taps < 200 {
            session.acknowledgeSideSwitchNotice()
            session.recordPoint(for: .teamA)
            taps += 1
        }
        XCTAssertTrue(session.isMatchOver)
    }

    func testActivationSendsEveryPendingMatchInOrder() throws {
        let first = try queuedMatch(), second = try queuedMatch()
        transport.simulateActivation()
        XCTAssertEqual(transport.sent.map(\.matchID), [first, second])
        let sent = try XCTUnwrap(transport.sent.first)
        XCTAssertEqual(sent.schema, 1)
        XCTAssertEqual(try SyncedMatchPayload.decode(from: sent.payload).id, first)
    }

    func testNothingIsSentBeforeTheSessionIsActivated() throws {
        _ = try queuedMatch()
        transport.isActivated = false
        transport.simulateActivation()
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testAnOrphanPendingIDIsDroppedAndNothingIsSent() throws {
        let orphan = UUID()
        pending.markPending(orphan)
        transport.simulateActivation()
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertFalse(pending.isPending(orphan))
    }

    func testAMatchWithAnOutstandingTransferIsNotQueuedAgain() throws {
        let id = try queuedMatch()
        transport.outstanding = [id]
        transport.simulateActivation()
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertTrue(pending.isPending(id), "still waiting for the phone")
    }

    func testSendingKeepsTheMatchPendingUntilTheAcknowledgement() throws {
        let id = try queuedMatch()
        transport.simulateActivation()
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertTrue(pending.isPending(id), "a finished transfer is not an acknowledgement")
        XCTAssertNotNil(try repository.fetchMatchRecord(id: id))
    }

    func testTheAcknowledgementConfirmsAndDeletesTheLocalRecord() throws {
        let id = try queuedMatch()
        transport.simulateActivation()
        transport.simulateAcknowledgement(id)
        XCTAssertFalse(pending.isPending(id))
        XCTAssertNil(try repository.fetchMatchRecord(id: id))
    }

    func testAnAcknowledgementForAnUnknownMatchChangesNothing() throws {
        let kept = try queuedMatch()
        transport.simulateAcknowledgement(UUID())
        XCTAssertTrue(pending.isPending(kept))
        XCTAssertNotNil(try repository.fetchMatchRecord(id: kept))
    }

    func testTheMatchOnTheMatchOverScreenIsNeverSentOrDeleted() throws {
        finishMatchOnSession()
        let id = try XCTUnwrap(session.undoableSavedMatchID)
        XCTAssertTrue(pending.isPending(id))

        transport.simulateActivation()
        XCTAssertTrue(transport.sent.isEmpty, "it can still be undone")

        transport.simulateAcknowledgement(id)
        XCTAssertNotNil(try repository.fetchMatchRecord(id: id), "an ack must not delete the undoable record")
        XCTAssertTrue(pending.isPending(id))
    }

    func testDoneSendsTheFinishedMatch() throws {
        finishMatchOnSession()
        let id = try XCTUnwrap(session.undoableSavedMatchID)
        try session.dismissFinishedMatch()
        XCTAssertEqual(transport.sent.map(\.matchID), [id])
        XCTAssertNil(session.undoableSavedMatchID)
    }

    func testUndoBeforeDoneNeverSendsTheMatch() throws {
        finishMatchOnSession()
        let id = try XCTUnwrap(session.undoableSavedMatchID)
        session.undo()
        transport.simulateActivation()
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertFalse(pending.isPending(id))
        XCTAssertNil(try repository.fetchMatchRecord(id: id))
    }

    func testAFailedDoneDoesNotSync() throws {
        finishMatchOnSession()
        session.undo()
        // Replay the deciding point but make Done's save fail, so Done throws.
        session.saveFailureForTesting = NSError(domain: "x", code: 1)
        var taps = 0
        while !session.isMatchOver, taps < 50 { session.acknowledgeSideSwitchNotice(); session.recordPoint(for: .teamA); taps += 1 }
        XCTAssertThrowsError(try session.dismissFinishedMatch())
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testTheTransportIsStartedAndRetriedAtTheNextTrigger() throws {
        XCTAssertTrue(transport.started)
        let id = try queuedMatch()
        // A first attempt that the system dropped (not outstanding, not acked)
        // is simply queued again at the next launch or Done.
        transport.simulateActivation()
        transport.simulateActivation()
        XCTAssertEqual(transport.sent.map(\.matchID), [id, id])
    }

    func testAFailedLocalDeleteOnAcknowledgementLeavesTheIDPending() throws {
        let id = try queuedMatch()
        coordinator.deleteRecord = { _ in throw NSError(domain: "x", code: 1) }
        transport.simulateAcknowledgement(id)
        XCTAssertTrue(pending.isPending(id), "kept so the next acknowledgement retries the delete")
        XCTAssertNotNil(try repository.fetchMatchRecord(id: id))

        coordinator.deleteRecord = { [repository] in try repository!.deleteMatch($0) }
        transport.simulateAcknowledgement(id)
        XCTAssertFalse(pending.isPending(id))
        XCTAssertNil(try repository.fetchMatchRecord(id: id))
    }

    func testAnAcknowledgementForAStaleRecordIsIgnoredAndItIsNeverSent() throws {
        finishMatchOnSession()
        let id = try XCTUnwrap(session.undoableSavedMatchID)
        session.deleteMatchRecord = { _ in throw NSError(domain: "x", code: 1) }
        session.undo()  // the delete fails: the record is kept as stale
        XCTAssertNil(session.undoableSavedMatchID)
        XCTAssertEqual(session.heldBackMatchIDs, [id])

        transport.simulateActivation()
        XCTAssertTrue(transport.sent.isEmpty, "a stale record is not a match")
        transport.simulateAcknowledgement(id)
        XCTAssertTrue(pending.isPending(id))
        XCTAssertNotNil(try repository.fetchMatchRecord(id: id))
    }
}
