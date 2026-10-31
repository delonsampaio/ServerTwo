import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

/// The phone's side of Watch sync as the app wires it: the receiver imports on
/// the main context while `ActiveMatchController` works in its own context of
/// the same container (as `MyApp` builds them), so these check that the demo
/// gate and its counter really see an imported match.
@MainActor
final class WatchSyncReceiveTests: XCTestCase {
    private struct Ack: PhoneSyncAcknowledging {
        func acknowledge(matchID: UUID) {}
    }

    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private var controller: ActiveMatchController!
    private var seen: SeenMatchIDStore!

    override func setUp() async throws {
        container = try PersistenceContainer.makeInMemoryContainer()
        let suite = "WatchSyncReceiveTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        seen = SeenMatchIDStore(suiteName: suite)
        controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        controller.proUnlocked = false
        controller.demoMatchLimit = 1
    }

    private func makeReceiver(countImports: Bool) -> WatchMatchReceiver {
        WatchMatchReceiver(
            repository: MatchRepository(modelContext: container.mainContext, seenMatchIDs: seen)
        ) { [controller] before in
            if countImports { controller?.recordCompletedMatchSaved(historyCountBeforeSave: before) }
        }
    }

    /// A real finished match, built the way the Watch builds one.
    private func makeIncoming() throws -> IncomingSyncedMatch {
        let other = MatchRepository(
            modelContext: ModelContext(try PersistenceContainer.makeInMemoryContainer()),
            seenMatchIDs: SeenMatchIDStore(suiteName: "WatchSyncReceiveTests-\(UUID().uuidString)")
        )
        let match = PickleballMatch(
            configuration: GameConfiguration(), matchFormat: .bestOfOne,
            firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil
        )
        var taps = 0
        while !match.isMatchOver, taps < 200 { match.recordPoint(for: .teamA); taps += 1 }
        let record = try other.saveCompletedMatch(match, teamAName: "Team A", teamBName: "Team B", startedAt: Date().addingTimeInterval(-600))
        let payload = SyncedMatchPayload(record: record)
        return try XCTUnwrap(IncomingSyncedMatch(
            userInfo: SyncedMatchMessage(matchID: payload.id, payload: try payload.encoded()).userInfo
        ))
    }

    func testTheControllersContextSeesAnImportedMatch() throws {
        XCTAssertTrue(controller.canStartNewMatch, "precondition: nothing played yet")
        // The counter is switched off: only the history the controller reads
        // can make it stop here.
        XCTAssertEqual(makeReceiver(countImports: false).receive(try makeIncoming(), acknowledger: Ack()), .imported)
        XCTAssertFalse(controller.canStartNewMatch)
    }

    func testAnImportedMatchCountsOnceTowardTheDemoLimit() throws {
        let receiver = makeReceiver(countImports: true)
        let incoming = try makeIncoming()
        receiver.receive(incoming, acknowledger: Ack())
        XCTAssertEqual(defaults.integer(forKey: "lifetimeCompletedMatchCount"), 1)

        // A resend and a re-delivery after deleting the match change nothing.
        receiver.receive(incoming, acknowledger: Ack())
        let repository = MatchRepository(modelContext: container.mainContext, seenMatchIDs: seen)
        try repository.deleteMatch(try XCTUnwrap(try repository.fetchMatchHistory().first))
        receiver.receive(incoming, acknowledger: Ack())
        XCTAssertEqual(defaults.integer(forKey: "lifetimeCompletedMatchCount"), 1)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
        XCTAssertFalse(controller.canStartNewMatch, "deleting the match does not give the demo match back")
    }

    func testARejectedMatchIsNotCounted() throws {
        var payload = try XCTUnwrap(try makeIncoming().payload)
        payload.winningTeamRawValue = Team.teamB.rawValue
        let bad = IncomingSyncedMatch(matchID: payload.id, schema: 1, payload: payload)
        XCTAssertEqual(makeReceiver(countImports: true).receive(bad, acknowledger: Ack()), .rejected(.winnerMismatch))
        XCTAssertEqual(defaults.integer(forKey: "lifetimeCompletedMatchCount"), 0)
        XCTAssertTrue(controller.canStartNewMatch)
    }
}

@MainActor
final class ScreenRefreshTimingTests: XCTestCase {
    func testAMatchFromTheWatchReloadsImmediately() {
        XCTAssertEqual(ScreenRefreshTiming.timing(for: .matchSyncedFromWatch), .immediately)
    }

    func testEditsAndDeletesStillWaitForTheNextAppear() {
        XCTAssertEqual(ScreenRefreshTiming.timing(for: .matchPlayersEdited), .onNextAppear)
        XCTAssertEqual(ScreenRefreshTiming.timing(for: .matchDeleted), .onNextAppear)
    }

    func testOtherNotificationsAreIgnored() {
        XCTAssertNil(ScreenRefreshTiming.timing(for: Notification.Name("something.else")))
    }
}
