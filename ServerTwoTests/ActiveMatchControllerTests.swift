import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

/// Plays out one whole game for `winner` through the controller without
/// assuming who serves first (Rule 21.F.2: the first server alternates, so a
/// later game can start with the OTHER team serving and a winner who is
/// receiving must first win side-outs). Bounded so a bug fails instead of
/// hanging.
@MainActor
func playOutGame(
    _ controller: ActiveMatchController,
    winner: Team,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let target = (controller.match?.completedGames.count ?? 0) + 1
    var taps = 0
    while (controller.match?.completedGames.count ?? 0) < target, taps < 200 {
        controller.recordPoint(for: winner)
        taps += 1
    }
    XCTAssertEqual(controller.match?.completedGames.count, target, "the game never finished for \(winner)", file: file, line: line)
}

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

    /// iOS can kill the app between games. The relaunched controller used to
    /// restore the names but not who the players were, so finishing the
    /// resumed match saved it with no linked saved players and silently
    /// dropped it from W/L, streaks, chemistry and filters.
    func testResumedMatchStillLinksTheSavedPlayersWhenFinished() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let repository = MatchRepository(modelContext: ModelContext(container))
        let alice = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Alice"))
        let bob = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Bob"))
        let carol = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Carol"))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        let first = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(first, teamAName: "Alice & Bob", teamBName: "Carol", teamAPlayers: [alice, bob], teamBPlayers: [carol])
        first.recordPoint(for: .teamA)

        // A fresh controller over the same store and defaults is a relaunch.
        let resumed = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        XCTAssertNotNil(resumed.match)
        for _ in 1...10 { resumed.recordPoint(for: .teamA) }
        let record = try resumed.finishMatch()

        let teamA = try XCTUnwrap(record.teamSides?.first { $0.team == .teamA })
        let teamB = try XCTUnwrap(record.teamSides?.first { $0.team == .teamB })
        XCTAssertEqual(Set(teamA.players?.map(\.id) ?? []), [alice.id, bob.id])
        XCTAssertEqual(teamB.players?.map(\.id), [carol.id])
    }

    func testFinishAndCancelClearTheStoredPlayerIDs() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let alice = try XCTUnwrap(try MatchRepository(modelContext: ModelContext(container)).upsertSavedPlayer(name: "Alice"))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        typealias Keys = ActiveMatchController.Keys

        start(controller, teamAName: "Alice", teamBName: "B", teamAPlayers: [alice])
        XCTAssertEqual(defaults.stringArray(forKey: Keys.activeTeamAPlayerIDs), [alice.id.uuidString])
        XCTAssertEqual(defaults.stringArray(forKey: Keys.activeTeamBPlayerIDs), [String]())
        controller.cancelActiveMatch()
        XCTAssertNil(defaults.object(forKey: Keys.activeTeamAPlayerIDs))
        XCTAssertNil(defaults.object(forKey: Keys.activeTeamBPlayerIDs))

        start(controller, teamAName: "Alice", teamBName: "B", teamAPlayers: [alice])
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        _ = try controller.finishMatch()
        XCTAssertNil(defaults.object(forKey: Keys.activeTeamAPlayerIDs))
        XCTAssertNil(defaults.object(forKey: Keys.activeTeamBPlayerIDs))
    }

    func testResumeToleratesADeletedPlayerAndAnInvalidStoredID() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let viewRepository = MatchRepository(modelContext: ModelContext(container))
        let alice = try XCTUnwrap(try viewRepository.upsertSavedPlayer(name: "Alice"))
        let bob = try XCTUnwrap(try viewRepository.upsertSavedPlayer(name: "Bob"))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        let first = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(first, teamAName: "Alice", teamBName: "Bob", teamAPlayers: [alice], teamBPlayers: [bob])
        // Alice is deleted after the match began; a corrupt entry is stored too.
        try viewRepository.deleteSavedPlayer(alice)
        defaults.set(["not-a-uuid", alice.id.uuidString], forKey: ActiveMatchController.Keys.activeTeamAPlayerIDs)

        let resumed = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        for _ in 1...11 { resumed.recordPoint(for: .teamA) }
        let record = try resumed.finishMatch()

        let teamA = try XCTUnwrap(record.teamSides?.first { $0.team == .teamA })
        let teamB = try XCTUnwrap(record.teamSides?.first { $0.team == .teamB })
        XCTAssertEqual(teamA.players?.count ?? 0, 0)
        XCTAssertEqual(teamB.players?.map(\.id), [bob.id])
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

    func testCorrectScoresPersistsSnapshot() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: ModelContext(container), userDefaults: defaults)
        start(controller, teamAName: "A", teamBName: "B")
        controller.correctScores(teamA: 7, teamB: 4)

        let reread = try MatchRepository(modelContext: ModelContext(container))
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: nil)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 7)
        XCTAssertEqual(reread?.match.currentGame.state.teamBScore, 4)
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

    func testGameCompletionDatesStaysCorrectlySizedAcrossUndoAndReplay() throws {
        let (controller, _) = try makeController()
        start(controller, matchFormat: .bestOfThree, teamAName: "A", teamBName: "B")

        // Win game 1 outright (11-0).
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        XCTAssertEqual(controller.gameCompletionDates.count, 1)

        // Undo the game-winning point — this reverts completedGames back to
        // empty, which must shrink gameCompletionDates back to empty too, not
        // leave a stale premature timestamp sitting at index 0.
        controller.undo()
        XCTAssertEqual(controller.gameCompletionDates.count, 0)

        // Replay the real winning point for game 1.
        controller.recordPoint(for: .teamA)
        XCTAssertEqual(controller.gameCompletionDates.count, 1)

        // Win game 2 as well — now two completed games, two dates. (Not
        // asserting the two dates are distinct values: back-to-back Date()
        // captures with only a scoring loop between them is a real, if
        // small, flakiness risk without an injected clock — the array being
        // correctly *sized* is this test's actual claim, not that it holds
        // literally non-equal timestamps.)
        // Game 2 starts with the OTHER team serving (Rule 21.F.2), so Team A must win side-outs first; playOutGame doesn't assume a server.
        playOutGame(controller, winner: .teamA)
        XCTAssertEqual(controller.gameCompletionDates.count, 2)
    }

    func testGameCompletionDatesStaysCorrectlySizedWhenUndoingTheMatchDecidingPoint() throws {
        let (controller, _) = try makeController()
        start(controller, matchFormat: .bestOfThree, teamAName: "A", teamBName: "B")

        // Win game 1 outright (11-0).
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        XCTAssertEqual(controller.gameCompletionDates.count, 1)

        // Win game 2 as well — team A now wins the whole match 2-0.
        // Because this point ends the match itself (not just the game),
        // PickleballMatch never spins up a fresh currentGame afterward, so
        // currentGameIsCounted stays true going into the undo() below.
        // That's the branch of PickleballMatch.undo() the OTHER
        // gameCompletionDates test above never reaches: it only ever
        // undoes a point that wins a single game within an ongoing match,
        // which leaves currentGameIsCounted false and falls through to
        // the other removal branch (completedGames.popLast()). Both
        // branches happen to shrink completedGames.count by exactly 1, so
        // this test is the one that actually proves syncGameCompletionDates
        // is correct on the higher-risk path: undoing the point that wins
        // the entire match.
        // Game 2 starts with the OTHER team serving (Rule 21.F.2), so Team A must win side-outs first; playOutGame doesn't assume a server.
        playOutGame(controller, winner: .teamA)
        XCTAssertEqual(controller.gameCompletionDates.count, 2)

        // Undo the match-deciding point. This must shrink
        // gameCompletionDates from 2 back to 1 — not stay stuck at 2, and
        // not over-shrink to 0.
        controller.undo()
        XCTAssertEqual(controller.gameCompletionDates.count, 1)
    }

    func testGameCompletionDatesResetsToEmptyOnFreshMatch() throws {
        let (controller, _) = try makeController()
        start(controller, teamAName: "A", teamBName: "B")
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        XCTAssertEqual(controller.gameCompletionDates.count, 1)

        _ = try controller.finishMatch()

        // A brand new match must not inherit the previous match's dates.
        start(controller, teamAName: "C", teamBName: "D")
        XCTAssertEqual(controller.gameCompletionDates.count, 0)
    }

    func testGameCompletionDatesResetsToEmptyOnCancelActiveMatch() throws {
        let (controller, _) = try makeController()
        start(controller, teamAName: "A", teamBName: "B")
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        XCTAssertEqual(controller.gameCompletionDates.count, 1)

        controller.cancelActiveMatch()

        // An idle controller must never hold leftover timestamps from a
        // discarded match — same reasoning as the fresh-match case above,
        // just via the other path back to .idle.
        start(controller, teamAName: "C", teamBName: "D")
        XCTAssertEqual(controller.gameCompletionDates.count, 0)
    }

    func testGameCompletionDatesPreSizesWithNilsOnCrashResume() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let context = ModelContext(container)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        let firstController = ActiveMatchController(modelContext: context, userDefaults: defaults)
        start(firstController, matchFormat: .bestOfThree, teamAName: "A", teamBName: "B")
        // Win game 1 (11-0) — this persists an in-progress snapshot via the
        // existing persistSnapshot() call, which is what the second
        // controller below resumes from.
        for _ in 1...11 { firstController.recordPoint(for: .teamA) }
        XCTAssertEqual(firstController.gameCompletionDates.count, 1)

        // A fresh controller against the SAME context/defaults simulates a
        // crash/relaunch — its own gameCompletionDates starts empty, with no
        // memory of the dates the first controller tracked in memory.
        let resumedController = ActiveMatchController(modelContext: context, userDefaults: defaults)
        XCTAssertEqual(resumedController.gameCompletionDates, [nil])

        // Winning game 2 from here must APPEND a real date for game 2, not
        // overwrite game 1's nil or reset the array.
        // Game 2 starts with the OTHER team serving (Rule 21.F.2), so Team A must win side-outs first; playOutGame doesn't assume a server.
        playOutGame(resumedController, winner: .teamA)
        XCTAssertEqual(resumedController.gameCompletionDates.count, 2)
        XCTAssertNil(resumedController.gameCompletionDates[0])
        XCTAssertNotNil(resumedController.gameCompletionDates[1])
    }

    /// End-to-end proof that `gameCompletionDates` actually makes it into
    /// the persisted record, not just the controller's in-memory array —
    /// `finishMatch()` hands the array to `saveCompletedMatch`, which has a
    /// defaulted `gameCompletionDates: [Date?] = []` parameter; deleting the
    /// one argument that wires them together would compile cleanly and every
    /// other existing test would still pass, while every `GameRecord.completedAt`
    /// silently went nil forever in production. Found in the final
    /// whole-branch review, Important #1.
    func testFinishMatchPersistsGameCompletionDatesOntoEveryGameRecord() throws {
        let (controller, _) = try makeController()
        start(controller, matchFormat: .bestOfThree, teamAName: "A", teamBName: "B")

        // Win game 1 outright (11-0), then game 2 (11-0) — team A wins the
        // match 2-0, so both games have a real completion timestamp tracked
        // by the controller.
        for _ in 1...11 { controller.recordPoint(for: .teamA) }
        // Game 2 starts with the OTHER team serving (Rule 21.F.2), so Team A must win side-outs first; playOutGame doesn't assume a server.
        playOutGame(controller, winner: .teamA)

        let record = try controller.finishMatch()
        XCTAssertTrue(
            record.games?.allSatisfy { $0.completedAt != nil } ?? false,
            "Every persisted GameRecord must carry the completion date the controller tracked in memory — if finishMatch() stopped passing gameCompletionDates through, these would all be nil"
        )
    }

    /// `correctScores(teamA:teamB:)` calls `syncGameCompletionDates()` the
    /// same as `recordPoint`/`undo`, but only those two call sites were
    /// covered by a test — this exercises the sync helper via the correction
    /// call site, including the two-team flow that motivated the atomic API:
    /// 9-9 -> 12-11 must NOT complete a game (no date), and 12-10 must.
    func testCorrectScoresGrowsGameCompletionDatesOnlyWhenItWinsAGame() throws {
        let (controller, _) = try makeController()
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        start(controller, configuration: config, matchFormat: .bestOfThree, teamAName: "A", teamBName: "B")
        XCTAssertEqual(controller.gameCompletionDates.count, 0)

        controller.correctScores(teamA: 9, teamB: 9)
        controller.correctScores(teamA: 12, teamB: 11)   // in progress: no game completed
        XCTAssertEqual(controller.match?.completedGames.count, 0)
        XCTAssertEqual(controller.gameCompletionDates.count, 0)

        controller.correctScores(teamA: 12, teamB: 10)   // completed: game 1 ends
        XCTAssertEqual(controller.match?.completedGames.count, 1)
        XCTAssertEqual(controller.gameCompletionDates.count, 1)
    }
}
