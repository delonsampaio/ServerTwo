import XCTest
import SwiftData
@testable import PickleballKit

/// Players in a Watch match: names, the saved record, the remembered entries
/// (current match and per saved match), resume, and the payload that carries
/// them to the phone.
@MainActor
final class StandaloneMatchSessionPlayersTests: XCTestCase {
    private var suite = ""
    private var repository: MatchRepository!
    private var pending: PendingSyncStore!
    private var playersStore: WatchPlayersStore!
    private var transport: FakeWatchTransport!
    private var coordinator: WatchSyncCoordinator!
    private var session: StandaloneMatchSession!
    private var clock = Date(timeIntervalSince1970: 1_000)

    private let mike = SyncedPlayerRef(savedPlayerID: UUID(), name: "Mike")
    private let sarah = SyncedPlayerRef(name: "Sarah")
    private let ann = SyncedPlayerRef(name: "Ann")
    private let bo = SyncedPlayerRef(name: "Bo")

    override func setUp() async throws {
        suite = makeSyncSuite()
        let context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        repository = MatchRepository(modelContext: context, seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite()))
        pending = PendingSyncStore(suiteName: suite)
        playersStore = WatchPlayersStore(suiteName: suite)
        transport = FakeWatchTransport()
        session = makeSession()
        coordinator = WatchSyncCoordinator(
            repository: repository, pendingSync: pending, transport: transport, session: session
        )
        coordinator.start()
    }

    private func makeSession() -> StandaloneMatchSession {
        StandaloneMatchSession(
            repository: repository,
            pendingSync: pending,
            playersStore: playersStore,
            now: { [unowned self] in
                self.clock.addTimeInterval(60)
                return self.clock
            }
        )
    }

    private func startDoubles(_ players: WatchMatchPlayers, on session: StandaloneMatchSession? = nil) {
        (session ?? self.session).start(
            configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA, players: players
        )
    }

    private func finishMatch(_ session: StandaloneMatchSession? = nil) {
        let session = session ?? self.session!
        var taps = 0
        while !session.isMatchOver, taps < 200 {
            session.acknowledgeSideSwitchNotice()
            session.recordPoint(for: .teamA)
            taps += 1
        }
        XCTAssertTrue(session.isMatchOver)
    }

    private let fourPlayers = { (mike: SyncedPlayerRef, sarah: SyncedPlayerRef, ann: SyncedPlayerRef, bo: SyncedPlayerRef) in
        WatchMatchPlayers(teamA: [mike, sarah], teamB: [ann, bo])
    }

    // MARK: Start and names

    func testStartWithPlayersNamesTheTeamsAfterThem() {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        XCTAssertEqual(session.teamName(for: .teamA), "Mike & Sarah")
        XCTAssertEqual(session.teamName(for: .teamB), "Ann & Bo")
        XCTAssertEqual(session.spokenSummary(for: .teamA).prefix(12), "Mike & Sarah")
    }

    func testStartWithoutPlayersKeepsTheDefaultNames() {
        startDoubles(.empty)
        XCTAssertEqual(session.teamName(for: .teamA), "Team A")
        XCTAssertEqual(session.teamName(for: .teamB), "Team B")
        XCTAssertNil(playersStore.currentMatchPlayers)
    }

    func testOneSideCanBeNamedWhileTheOtherKeepsItsDefault() {
        startDoubles(WatchMatchPlayers(teamA: [mike]))
        XCTAssertEqual(session.teamName(for: .teamA), "Mike")
        XCTAssertEqual(session.teamName(for: .teamB), "Team B")
    }

    func testPlayersAreSlicedToThePlayMode() {
        session.start(
            configuration: GameConfiguration(playMode: .singles, scoringFormat: .sideOut),
            format: .bestOfOne, firstServingTeam: .teamA, players: fourPlayers(mike, sarah, ann, bo)
        )
        XCTAssertEqual(session.teamName(for: .teamA), "Mike")
        XCTAssertEqual(session.teamName(for: .teamB), "Ann")
        XCTAssertEqual(playersStore.currentMatchPlayers, WatchMatchPlayers(teamA: [mike], teamB: [ann]))
    }

    // MARK: Saved record and the entries kept for sync

    func testTheSavedRecordHasTheJoinedNamesAndTheEntriesAreKeptUntilAcknowledged() throws {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        finishMatch()
        let id = try XCTUnwrap(session.undoableSavedMatchID)
        let record = try XCTUnwrap(try repository.fetchMatchRecord(id: id))
        let sides = record.teamSides ?? []
        XCTAssertEqual(sides.first { $0.team == .teamA }?.displayName, "Mike & Sarah")
        XCTAssertEqual(sides.first { $0.team == .teamB }?.displayName, "Ann & Bo")
        XCTAssertEqual(playersStore.players(forSavedMatch: id), fourPlayers(mike, sarah, ann, bo))

        try session.dismissFinishedMatch()
        XCTAssertNil(playersStore.currentMatchPlayers, "the match in progress is over")
        XCTAssertNotNil(playersStore.players(forSavedMatch: id), "still needed until the phone has the match")
    }

    func testTheSentPayloadCarriesTheEntriesAndTheNames() throws {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        finishMatch()
        try session.dismissFinishedMatch()
        let message = try XCTUnwrap(transport.sent.first)
        let payload = try SyncedMatchPayload.decode(from: message.payload)
        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.teamAName, "Mike & Sarah")
        XCTAssertEqual(payload.teamBName, "Ann & Bo")
        XCTAssertEqual(payload.teamAPlayers, [mike, sarah])
        XCTAssertEqual(payload.teamBPlayers, [ann, bo])
    }

    func testAResendAfterARelaunchStillCarriesTheEntries() throws {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        finishMatch()
        try session.dismissFinishedMatch()
        // A fresh coordinator and session over the same stores, as after a relaunch.
        let relaunchedTransport = FakeWatchTransport()
        let relaunchedSession = makeSession()
        let relaunched = WatchSyncCoordinator(
            repository: repository, pendingSync: pending, transport: relaunchedTransport, session: relaunchedSession
        )
        relaunched.start()
        relaunchedTransport.simulateActivation()
        let payload = try SyncedMatchPayload.decode(from: try XCTUnwrap(relaunchedTransport.sent.first).payload)
        XCTAssertEqual(payload.teamAPlayers, [mike, sarah])
    }

    func testAMatchWithoutPlayersSendsTheOldShape() throws {
        startDoubles(.empty)
        finishMatch()
        try session.dismissFinishedMatch()
        let payload = try SyncedMatchPayload.decode(from: try XCTUnwrap(transport.sent.first).payload)
        XCTAssertNil(payload.teamAPlayers)
        XCTAssertNil(payload.teamBPlayers)
        XCTAssertEqual(payload.teamAName, "Team A")
    }

    func testTheAcknowledgementRemovesTheEntries() throws {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        finishMatch()
        let id = try XCTUnwrap(session.undoableSavedMatchID)
        try session.dismissFinishedMatch()
        transport.simulateAcknowledgement(id)
        XCTAssertNil(playersStore.players(forSavedMatch: id))
        XCTAssertFalse(pending.isPending(id))
    }

    func testUndoingTheDecidingPointRemovesTheSavedEntriesAndReplayingWritesThemAgain() throws {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        finishMatch()
        let first = try XCTUnwrap(session.undoableSavedMatchID)
        session.undo()
        XCTAssertNil(playersStore.players(forSavedMatch: first))
        XCTAssertEqual(session.teamName(for: .teamA), "Mike & Sarah", "the match goes on with the same players")
        XCTAssertNotNil(playersStore.currentMatchPlayers)

        finishMatch()
        let second = try XCTUnwrap(session.undoableSavedMatchID)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(playersStore.players(forSavedMatch: second)?.teamA, [mike, sarah])
    }

    func testAnOrphanPendingIDDropsItsEntries() throws {
        let orphan = UUID()
        pending.markPending(orphan)
        playersStore.setPlayers(WatchMatchPlayers(teamA: [mike]), forSavedMatch: orphan)
        transport.simulateActivation()
        XCTAssertNil(playersStore.players(forSavedMatch: orphan))
        XCTAssertFalse(pending.isPending(orphan))
    }

    func testEntriesOfMatchesThatAreNoLongerPendingArePruned() throws {
        let stray = UUID()
        playersStore.setPlayers(WatchMatchPlayers(teamA: [mike]), forSavedMatch: stray)
        transport.simulateActivation()
        XCTAssertNil(playersStore.players(forSavedMatch: stray))
    }

    func testAFailedSaveLeavesNoEntriesBehind() throws {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        session.saveFailureForTesting = NSError(domain: "x", code: 1)
        finishMatch()
        XCTAssertNil(session.undoableSavedMatchID)
        XCTAssertTrue(pending.pendingMatchIDs.isEmpty)
        // Done retries; the entries are written for the id that sticks.
        session.saveFailureForTesting = nil
        try session.dismissFinishedMatch()
        let id = try XCTUnwrap(pending.pendingMatchIDs.first)
        XCTAssertNotNil(playersStore.players(forSavedMatch: id))
    }

    // MARK: Finish, abandon, resume

    func testAbandoningClearsTheCurrentPlayers() {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        XCTAssertNotNil(playersStore.currentMatchPlayers)
        session.abandon()
        XCTAssertNil(playersStore.currentMatchPlayers)
        XCTAssertEqual(session.teamName(for: .teamA), "Team A")
    }

    func testARelaunchMidMatchKeepsTheNames() {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        session.recordPoint(for: .teamA)
        let relaunched = makeSession()
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertEqual(relaunched.teamName(for: .teamA), "Mike & Sarah")
        XCTAssertEqual(relaunched.teamName(for: .teamB), "Ann & Bo")
    }

    func testResumeWithoutStoredPlayersUsesTheDefaultNames() {
        startDoubles(.empty)
        session.recordPoint(for: .teamA)
        let relaunched = makeSession()
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertEqual(relaunched.teamName(for: .teamA), "Team A")
    }

    func testAStaleCurrentEntryIsClearedWhenThereIsNothingToResume() {
        playersStore.setCurrentMatchPlayers(fourPlayers(mike, sarah, ann, bo))
        XCTAssertFalse(makeSession().resumeIfNeeded())
        XCTAssertNil(playersStore.currentMatchPlayers)
    }

    func testStartingANewMatchReplacesTheCurrentPlayers() {
        startDoubles(fourPlayers(mike, sarah, ann, bo))
        session.abandon()
        startDoubles(WatchMatchPlayers(teamA: [ann]))
        XCTAssertEqual(playersStore.currentMatchPlayers, WatchMatchPlayers(teamA: [ann]))
        XCTAssertEqual(session.teamName(for: .teamB), "Team B")
    }

    // MARK: To the phone, end to end

    func testTheSentPayloadImportsOnThePhoneWithLinkedPlayers() throws {
        let phoneContext = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        let phone = MatchRepository(modelContext: phoneContext, seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite()))
        let known = try XCTUnwrap(phone.upsertSavedPlayer(name: "Mike"))
        let picked = SyncedPlayerRef(savedPlayerID: known.id, name: "Mike")

        startDoubles(WatchMatchPlayers(teamA: [picked, sarah], teamB: [ann]))
        finishMatch()
        try session.dismissFinishedMatch()
        let payload = try SyncedMatchPayload.decode(from: try XCTUnwrap(transport.sent.first).payload)

        XCTAssertEqual(try phone.importSyncedMatch(payload), .imported)
        XCTAssertEqual(try phone.fetchAllSavedPlayers().map(\.name).sorted(), ["Ann", "Mike", "Sarah"])
        let sides = try XCTUnwrap(try phone.fetchMatchRecord(id: payload.id)?.teamSides)
        XCTAssertEqual(sides.first { $0.team == .teamA }?.players?.map(\.name).sorted(), ["Mike", "Sarah"])
        XCTAssertEqual(sides.first { $0.team == .teamB }?.displayName, "Ann")
    }
}
