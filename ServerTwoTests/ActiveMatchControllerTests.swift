import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

@MainActor
final class ActiveMatchControllerTests: XCTestCase {
    private func makeController(
        userDefaultsSuite: String = UUID().uuidString
    ) throws -> (ActiveMatchController, UserDefaults) {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: userDefaultsSuite)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        return (controller, defaults)
    }

    /// Mirrors the real flow (Setup stages, the coin-flip screen confirms)
    /// in one call, since most of these tests care about the end state, not
    /// the two-step sequence itself — that sequence has its own dedicated
    /// tests below.
    private func start(
        _ controller: ActiveMatchController,
        configuration: GameConfiguration = GameConfiguration(),
        matchFormat: MatchFormat = .bestOfOne,
        firstServingTeam: Team = .teamA,
        teamAName: String,
        teamBName: String,
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = []
    ) {
        controller.stageMatch(PendingMatchSetup(
            configuration: configuration,
            matchFormat: matchFormat,
            teamAName: teamAName,
            teamBName: teamBName,
            teamAPlayerIDs: teamAPlayers.map(\.id),
            teamBPlayerIDs: teamBPlayers.map(\.id)
        ))
        controller.confirmFirstServe(firstServingTeam)
    }

    func testStartNewMatchCreatesLiveMatchWithGivenNamesAndPersistsSnapshot() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(controller, teamAName: "The Smashers", teamBName: "Net Ninjas")
        XCTAssertNotNil(controller.match)
        XCTAssertEqual(controller.teamAName, "The Smashers")
        XCTAssertEqual(controller.teamBName, "Net Ninjas")

        // The test name promises a persisted snapshot — assert it, don't just
        // assert the in-memory state.
        let reread = try MatchRepository(modelContext: ModelContext(container))
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: nil)
        XCTAssertNotNil(reread, "confirmFirstServe should persist an in-progress snapshot immediately")
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(reread?.match.currentGame.state.teamBScore, 0)
        XCTAssertEqual(reread?.match.currentGame.state.servingTeam, .teamA)
    }

    func testStartNewMatchFallsBackToDefaultNamesWhenBlank() throws {
        let (controller, _) = try makeController()
        start(controller, teamAName: "   ", teamBName: "")
        XCTAssertEqual(controller.teamAName, "Team A")
        XCTAssertEqual(controller.teamBName, "Team B")
    }

    func testStageMatchSetsPendingMatchSetupWithoutCreatingAMatch() throws {
        let (controller, _) = try makeController()
        controller.stageMatch(PendingMatchSetup(
            configuration: GameConfiguration(),
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            teamAPlayerIDs: [],
            teamBPlayerIDs: []
        ))
        XCTAssertNotNil(controller.pendingMatchSetup, "stageMatch should make the coin-flip screen appear")
        XCTAssertNil(controller.match, "PickleballMatch can't exist yet — firstServingTeam isn't decided")
    }

    func testConfirmFirstServeTurnsAStagedSetupIntoALiveMatch() throws {
        let (controller, _) = try makeController()
        controller.stageMatch(PendingMatchSetup(
            configuration: GameConfiguration(),
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            teamAPlayerIDs: [],
            teamBPlayerIDs: []
        ))
        controller.confirmFirstServe(.teamB)
        XCTAssertNil(controller.pendingMatchSetup, "The staged setup should be consumed")
        XCTAssertNotNil(controller.match)
        XCTAssertEqual(controller.match?.currentGame.state.servingTeam, .teamB)
    }

    func testConfirmFirstServeIsANoOpWithNothingStaged() throws {
        let (controller, _) = try makeController()
        controller.confirmFirstServe(.teamA)
        XCTAssertNil(controller.match, "Confirming with nothing staged must not conjure a match out of nowhere")
    }

    func testCancelPendingMatchDiscardsTheStagedSetup() throws {
        let (controller, _) = try makeController()
        controller.stageMatch(PendingMatchSetup(
            configuration: GameConfiguration(),
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            teamAPlayerIDs: [],
            teamBPlayerIDs: []
        ))
        controller.cancelPendingMatch()
        XCTAssertNil(controller.pendingMatchSetup)
        XCTAssertNil(controller.match)
    }

    func testResumeIfNeededRestoresMatchStartedAtAndNames() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!

        let first = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(first, matchFormat: .bestOfThree, teamAName: "The Smashers", teamBName: "Net Ninjas")
        first.recordPoint(for: .teamA)
        first.recordPoint(for: .teamA)

        // A fresh controller against the same store/defaults simulates a relaunch.
        let resumed = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        XCTAssertNotNil(resumed.match)
        XCTAssertEqual(resumed.match?.currentGame.state.teamAScore, 2)
        XCTAssertEqual(resumed.teamAName, "The Smashers")
        XCTAssertEqual(resumed.teamBName, "Net Ninjas")
    }

    /// A staged-but-not-yet-flipped match is never persisted — only an
    /// active match's snapshot is. Accepted trade-off: a crash/relaunch
    /// during the coin-flip screen loses that staged setup, same as it
    /// always lost player attribution across a resume.
    func testResumeIfNeededDoesNotRestoreAStagedButUnconfirmedMatch() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!

        let first = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        first.stageMatch(PendingMatchSetup(
            configuration: GameConfiguration(),
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            teamAPlayerIDs: [],
            teamBPlayerIDs: []
        ))

        let resumed = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        XCTAssertNil(resumed.match)
        XCTAssertNil(resumed.pendingMatchSetup, "A staged setup is in-memory only and must not resurface after a relaunch")
    }

    func testResumeIfNeededDoesNothingWhenAlreadyHasALiveMatch() throws {
        let (controller, _) = try makeController()
        start(controller, teamAName: "A", teamBName: "B")
        let matchBeforeResume = controller.match
        controller.resumeIfNeeded()
        XCTAssertTrue(controller.match === matchBeforeResume)
    }

    func testRecordPointPersistsSnapshotAfterEveryPoint() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(controller, teamAName: "A", teamBName: "B")
        controller.recordPoint(for: .teamA)

        let reread = try MatchRepository(modelContext: ModelContext(container))
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: nil)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 1)
    }

    func testUndoPersistsSnapshot() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(controller, teamAName: "A", teamBName: "B")
        controller.recordPoint(for: .teamA)
        controller.undo()

        let reread = try MatchRepository(modelContext: ModelContext(container))
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: nil)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 0)
    }

    func testCorrectScorePersistsSnapshot() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(controller, teamAName: "A", teamBName: "B")
        controller.correctScore(team: .teamA, to: 7)

        let reread = try MatchRepository(modelContext: ModelContext(container))
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: nil)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 7)
    }

    func testRequestTimeoutPersistsSnapshotOnlyWhenTimeoutActuallyStarts() throws {
        // Negative path: no timeouts available, so nothing starts.
        let (controller, _) = try makeController()
        start(controller, configuration: GameConfiguration(timeoutsPerTeam: 0), teamAName: "A", teamBName: "B")
        XCTAssertFalse(controller.requestTimeout(for: .teamA))

        // Positive path: a timeout that actually starts must be persisted.
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let withTimeouts = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(withTimeouts, configuration: GameConfiguration(timeoutsPerTeam: 2), teamAName: "A", teamBName: "B")
        XCTAssertTrue(withTimeouts.requestTimeout(for: .teamA))
        XCTAssertEqual(withTimeouts.match?.currentGame.state.teamATimeoutsRemaining, 1)

        let reread = try MatchRepository(modelContext: ModelContext(container))
            .loadInProgressMatch(proUnlocked: withTimeouts.proUnlocked, demoPointCap: nil)
        XCTAssertEqual(
            reread?.match.currentGame.state.teamATimeoutsRemaining,
            1,
            "The decremented timeout count should survive a reload"
        )
    }

    func testFinishMatchSavesToHistoryClearsLiveMatchAndClearsStoredNames() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        start(controller, configuration: config, teamAName: "A", teamBName: "B")
        for _ in 1...11 { controller.recordPoint(for: .teamA) }

        let record = try controller.finishMatch()
        XCTAssertEqual(record.winningTeam, .teamA)
        XCTAssertNil(controller.match)

        let history = try MatchRepository(modelContext: ModelContext(container)).fetchMatchHistory()
        XCTAssertEqual(history.count, 1)

        // A fresh controller must not think there's a match to resume.
        let afterRelaunch = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        XCTAssertNil(afterRelaunch.match)
    }

    func testFinishMatchThrowsAndLeavesMatchIntactWhenMatchNotOver() throws {
        let (controller, _) = try makeController()
        start(controller, teamAName: "A", teamBName: "B")
        controller.recordPoint(for: .teamA)

        XCTAssertThrowsError(try controller.finishMatch()) { error in
            XCTAssertEqual(error as? MatchRepositoryError, .matchNotOver)
        }
        XCTAssertNotNil(controller.match)
    }

    func testCanStartNewMatchIsFalseOnlyAfterTheDemoMatchLimitIsUsedUp() throws {
        let (controller, _) = try makeController()
        controller.demoMatchLimit = 1
        XCTAssertTrue(controller.canStartNewMatch, "A free user with no match history yet should be able to start one")

        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        start(controller, configuration: config, teamAName: "A", teamBName: "B")
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        _ = try controller.finishMatch()

        XCTAssertFalse(controller.canStartNewMatch, "The free demo limit should be used up after one completed match")
    }

    func testUnlockProLiftsTheDemoMatchLimitAndPersistsAcrossRelaunch() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        controller.demoMatchLimit = 1

        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        start(controller, configuration: config, teamAName: "A", teamBName: "B")
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        _ = try controller.finishMatch()
        XCTAssertFalse(controller.canStartNewMatch)

        controller.unlockPro()
        XCTAssertTrue(controller.proUnlocked)
        XCTAssertTrue(controller.canStartNewMatch, "Unlocking Pro should lift the demo match limit immediately")

        // A fresh controller against the same store/defaults (a relaunch)
        // keeps both the entitlement and the lifted limit, rather than
        // re-paywalling a user who has already paid.
        let afterRelaunch = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        XCTAssertTrue(afterRelaunch.proUnlocked)
        XCTAssertTrue(afterRelaunch.canStartNewMatch)
    }

    func testFinishMatchAttributesSavedPlayersByIDAcrossContexts() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let viewContext = ModelContext(container)
        let viewRepository = MatchRepository(modelContext: viewContext)
        let alice = try XCTUnwrap(try viewRepository.upsertSavedPlayer(name: "Alice"))

        // A SEPARATE context, exactly as `MyApp.init` builds it — the
        // controller must not carry `alice` (a view-context object) into it.
        let controller = ActiveMatchController(
            modelContext: ModelContext(container),
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        start(controller, teamAName: "Alice", teamBName: "Opponent", teamAPlayers: [alice])
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        let record = try controller.finishMatch()

        let rereadContext = ModelContext(container)
        let savedAlice = try XCTUnwrap(
            try MatchRepository(modelContext: rereadContext).fetchAllSavedPlayers().first { $0.name == "Alice" }
        )
        let teamASide = try XCTUnwrap(record.teamSides?.first { $0.team == .teamA })
        XCTAssertEqual(teamASide.players?.map(\.id), [savedAlice.id], "The player attributed to team A must be the same identity created via the view's context")
    }

    func testFinishMatchDropsAPlayerDeletedWhileTheMatchWasInProgress() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let viewContext = ModelContext(container)
        let viewRepository = MatchRepository(modelContext: viewContext)
        let alice = try XCTUnwrap(try viewRepository.upsertSavedPlayer(name: "Alice"))

        let controller = ActiveMatchController(
            modelContext: ModelContext(container),
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        start(controller, teamAName: "Alice", teamBName: "Opponent", teamAPlayers: [alice])

        // Alice is deleted (e.g. via Manage Players) while the match is
        // still in progress, through the SAME context that created her —
        // this must not prevent the match from being saved.
        try viewRepository.deleteSavedPlayer(alice)

        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        let record = try controller.finishMatch()

        let teamASide = try XCTUnwrap(record.teamSides?.first { $0.team == .teamA })
        XCTAssertEqual(teamASide.players?.count ?? 0, 0, "A player deleted mid-match must be silently dropped, not block the save or resurrect the deleted row")
    }

    func testProUnlockedPersistsAcrossControllerInstances() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let first = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        first.unlockPro()

        let second = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        XCTAssertTrue(second.proUnlocked)
    }
}
