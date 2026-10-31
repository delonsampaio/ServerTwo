import XCTest
import SwiftData
@testable import PickleballKit

@MainActor
final class StandaloneMatchSessionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var context: ModelContext!
    private var repository: MatchRepository!
    private var clock = Date(timeIntervalSince1970: 1_000)

    override func setUp() async throws {
        let suite = "StandaloneMatchSessionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        repository = MatchRepository(modelContext: context)
    }

    private func makeSession() -> StandaloneMatchSession {
        StandaloneMatchSession(
            repository: repository,
            pendingSync: PendingSyncStore(userDefaults: defaults),
            now: { [unowned self] in
                self.clock.addTimeInterval(60)
                return self.clock
            }
        )
    }

    /// Taps `team` until the current game ends (bounded so a bug fails
    /// instead of hanging); in side-out scoring only the serving team scores,
    /// so a receiving winner has to win the side-outs first.
    private func playOutGame(_ session: StandaloneMatchSession, winner: Team) {
        var taps = 0
        while !session.isGameOver, !session.isMatchOver, taps < 200 {
            session.acknowledgeSideSwitchNotice()  // the notice holds scoring until dismissed
            session.recordPoint(for: winner)
            taps += 1
        }
        XCTAssertTrue(session.isGameOver || session.isMatchOver)
    }

    /// `count` taps for `team`, dismissing the side-switch notice that holds
    /// scoring when the game crosses its threshold.
    private func tap(_ session: StandaloneMatchSession, _ team: Team, times count: Int) {
        for _ in 0..<count {
            session.acknowledgeSideSwitchNotice()
            session.recordPoint(for: team)
        }
    }

    // MARK: Basic scoring

    func testStartPutsTheFirstServerOnServerTwoInDoublesSideOut() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamB)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.servingTeam, .teamB)
        XCTAssertEqual(session.serverNumber, .two)  // 0-0-2 start
        XCTAssertEqual(session.score(for: .teamA), 0)
        XCTAssertEqual(session.currentGameIndex, 0)
    }

    func testOnlyTheServingTeamScoresInSideOut() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        XCTAssertEqual(session.recordPoint(for: .teamA), .point)
        XCTAssertEqual(session.score(for: .teamA), 1)
        // Receiving team wins the rally while Server 2 is up: side out.
        XCTAssertEqual(session.recordPoint(for: .teamB), .sideOut)
        XCTAssertEqual(session.servingTeam, .teamB)
        XCTAssertEqual(session.serverNumber, .one)
        XCTAssertEqual(session.score(for: .teamB), 0)
        // Server 1 loses: second server, same team.
        XCTAssertEqual(session.recordPoint(for: .teamA), .secondServer)
        XCTAssertEqual(session.servingTeam, .teamB)
        XCTAssertEqual(session.serverNumber, .two)
    }

    func testCaptionAndSpokenLabelFollowThePhoneWording() {
        let doubles = makeSession()
        doubles.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        doubles.recordPoint(for: .teamA)
        XCTAssertEqual(doubles.servingCaption(for: .teamA), "SERVER 2")
        XCTAssertNil(doubles.servingCaption(for: .teamB))
        XCTAssertEqual(doubles.spokenSummary(for: .teamA), "Team A, 1 point, serving, server 2")
        XCTAssertEqual(doubles.spokenSummary(for: .teamB), "Team B, 0 points")

        let singles = makeSession()
        singles.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamB)
        XCTAssertEqual(singles.servingCaption(for: .teamB), "SERVING")
        XCTAssertEqual(singles.spokenSummary(for: .teamB), "Team B, 0 points, serving")

        let rally = makeSession()
        rally.start(configuration: GameConfiguration(scoringFormat: .rally(freeze: false)), format: .bestOfOne, firstServingTeam: .teamA)
        XCTAssertEqual(rally.servingCaption(for: .teamA), "SERVING")
    }

    func testFullGameToElevenEndsTheMatchInABestOfOne() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 10)
        XCTAssertFalse(session.isMatchOver)
        XCTAssertEqual(session.recordPoint(for: .teamA), .matchOver)
        XCTAssertTrue(session.isMatchOver)
        XCTAssertEqual(session.matchWinner, .teamA)
        XCTAssertEqual(session.gamesWon(for: .teamA), 1)
        XCTAssertFalse(session.isGameOver, "isGameOver is the between-games state; a decided match is isMatchOver")
        // Scoring is closed once the match is decided.
        XCTAssertEqual(session.recordPoint(for: .teamB), .ignored)
    }

    func testWinByTwoNeedsTwoClear() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 10)                             // 10-0
        tap(session, .teamB, times: 11)                             // B side-out, then scores to 10-10
        XCTAssertEqual(session.score(for: .teamA), 10)
        XCTAssertEqual(session.score(for: .teamB), 10)
        session.recordPoint(for: .teamB)                            // 10-11 does not end it
        XCTAssertFalse(session.isMatchOver)
        session.recordPoint(for: .teamB)                            // 10-12 does
        XCTAssertTrue(session.isMatchOver)
        XCTAssertEqual(session.matchWinner, .teamB)
    }

    func testRallyScoringPointsGoToTheRallyWinner() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(scoringFormat: .rally(freeze: false)), format: .bestOfOne, firstServingTeam: .teamA)
        XCTAssertEqual(session.recordPoint(for: .teamB), .point)
        XCTAssertEqual(session.score(for: .teamB), 1)
        XCTAssertEqual(session.servingTeam, .teamB)
        XCTAssertEqual(session.score(for: .teamA), 0)
    }

    // MARK: Games, undo, side switch

    func testBestOfThreeAlternatesTheInitialServerAndShowsASummaryBetweenGames() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfThree, firstServingTeam: .teamA)
        playOutGame(session, winner: .teamA)

        XCTAssertTrue(session.isGameOver)
        XCTAssertFalse(session.isMatchOver)
        let summary = try XCTUnwrap(session.lastCompletedGame)
        XCTAssertEqual(summary.gameNumber, 1)
        XCTAssertEqual(summary.winner, .teamA)
        XCTAssertEqual(summary.winnerScore, 11)
        XCTAssertEqual(summary.loserScore, 0)
        XCTAssertEqual(summary.nextServingTeam, .teamB, "Rule 21.F.2: the other team serves first")
        XCTAssertEqual(session.gamesWon(for: .teamA), 1)
        // While the summary is up a stray tap must not score in the next game.
        XCTAssertEqual(session.recordPoint(for: .teamB), .ignored)

        session.startNextGame()
        XCTAssertFalse(session.isGameOver)
        XCTAssertEqual(session.currentGameIndex, 1)
        XCTAssertEqual(session.servingTeam, .teamB)

        playOutGame(session, winner: .teamB)
        XCTAssertTrue(session.isGameOver)
        XCTAssertEqual(session.lastCompletedGame?.nextServingTeam, .teamA, "alternates again, whoever won")
        session.startNextGame()
        XCTAssertEqual(session.servingTeam, .teamA)
        playOutGame(session, winner: .teamB)
        XCTAssertTrue(session.isMatchOver)
        XCTAssertEqual(session.matchWinner, .teamB)
        XCTAssertNil(session.lastCompletedGame?.nextServingTeam)
        XCTAssertEqual(session.completedGameScores.count, 3)
    }

    func testUndoAcrossAGameBoundaryRestoresTheDecidedGame() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfThree, firstServingTeam: .teamA)
        playOutGame(session, winner: .teamA)
        session.startNextGame()
        XCTAssertEqual(session.currentGameIndex, 1)

        session.undo()  // reverses game 1's winning point
        XCTAssertEqual(session.currentGameIndex, 0)
        XCTAssertEqual(session.score(for: .teamA), 10)
        XCTAssertEqual(session.gamesWon(for: .teamA), 0)
        XCTAssertFalse(session.isGameOver)
        XCTAssertEqual(session.servingTeam, .teamA)
    }

    func testUndoFromTheGameOverScreenReturnsToScoring() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfThree, firstServingTeam: .teamA)
        playOutGame(session, winner: .teamA)
        XCTAssertTrue(session.isGameOver)
        session.undo()
        XCTAssertFalse(session.isGameOver)
        XCTAssertEqual(session.score(for: .teamA), 10)
        XCTAssertEqual(session.gamesWon(for: .teamA), 0)
    }

    func testSideSwitchNoticeAppearsOnlyInTheLastGame() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfThree, firstServingTeam: .teamA)
        // Game 1 (not the last game): crossing 6 raises nothing.
        tap(session, .teamA, times: 6)
        XCTAssertNil(session.sideSwitchNotice)
        playOutGame(session, winner: .teamA)
        session.startNextGame()
        playOutGame(session, winner: .teamB)   // game 2 to B: 1-1
        session.startNextGame()
        // Game 3 is the deciding game: the notice fires at 6, once.
        let server = session.servingTeam
        for _ in 0..<5 { session.recordPoint(for: server) }
        XCTAssertNil(session.sideSwitchNotice)
        session.recordPoint(for: server)
        XCTAssertEqual(session.sideSwitchNotice, .switchSides)
        // Scoring is held until the players acknowledge it.
        XCTAssertEqual(session.recordPoint(for: server), .ignored)
        session.acknowledgeSideSwitchNotice()
        XCTAssertNil(session.sideSwitchNotice)
        XCTAssertEqual(session.recordPoint(for: server), .point)
        XCTAssertNil(session.sideSwitchNotice, "only once per game")
    }

    func testSideSwitchNoticeInASingleGameAndSwitchBackOnUndo() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        for _ in 0..<6 { session.recordPoint(for: .teamA) }
        XCTAssertEqual(session.sideSwitchNotice, .switchSides)
        session.acknowledgeSideSwitchNotice()
        session.undo()  // back to 5-0: the teams go back
        XCTAssertEqual(session.sideSwitchNotice, .switchBack)
    }

    func testUndoWhileANoticeIsPendingDropsItWithoutAnOppositePrompt() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        for _ in 0..<6 { session.recordPoint(for: .teamA) }
        XCTAssertEqual(session.sideSwitchNotice, .switchSides)
        session.undo()
        XCTAssertNil(session.sideSwitchNotice)
    }

    func testUndoOnAFreshMatchIsANoOp() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        XCTAssertFalse(session.canUndo)
        session.undo()
        XCTAssertEqual(session.score(for: .teamA), 0)
    }

    // MARK: Persistence

    func testSnapshotIsSavedAndAFreshSessionResumesMidGame() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfThree, firstServingTeam: .teamB)
        session.recordPoint(for: .teamB)
        session.recordPoint(for: .teamA)
        session.recordPoint(for: .teamB)

        let relaunched = makeSession()
        XCTAssertFalse(relaunched.isActive)
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertEqual(relaunched.score(for: .teamB), session.score(for: .teamB))
        XCTAssertEqual(relaunched.score(for: .teamA), session.score(for: .teamA))
        XCTAssertEqual(relaunched.servingTeam, session.servingTeam)
        XCTAssertEqual(relaunched.serverNumber, session.serverNumber)
        XCTAssertTrue(relaunched.canUndo)
        XCTAssertFalse(relaunched.isGameOver)
        XCTAssertNil(relaunched.sideSwitchNotice)
    }

    func testResumeBetweenGamesShowsTheGameOverScreenAgain() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfThree, firstServingTeam: .teamA)
        playOutGame(session, winner: .teamA)

        let relaunched = makeSession()
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertTrue(relaunched.isGameOver)
        XCTAssertEqual(relaunched.lastCompletedGame?.nextServingTeam, .teamB)
    }

    func testResumeWithNothingSavedReturnsFalse() {
        XCTAssertFalse(makeSession().resumeIfNeeded())
    }

    func testResumedMatchPastTheThresholdDoesNotAnnounceASwitchItAlreadyMade() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        for _ in 0..<6 { session.recordPoint(for: .teamA) }
        session.acknowledgeSideSwitchNotice()

        let relaunched = makeSession()
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertNil(relaunched.sideSwitchNotice)
        XCTAssertEqual(relaunched.recordPoint(for: .teamA), .point)
        XCTAssertNil(relaunched.sideSwitchNotice)
    }

    func testFinishingSavesTheMatchRecordAndRecordsItAsPendingSync() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfThree, firstServingTeam: .teamA)
        playOutGame(session, winner: .teamA)
        session.startNextGame()
        playOutGame(session, winner: .teamA)
        XCTAssertTrue(session.isMatchOver)

        let record = try session.finish()
        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, record.id)
        XCTAssertEqual(record.winningTeam, .teamA)
        XCTAssertEqual(record.matchFormat, .bestOfThree)
        let games = (record.games ?? []).sorted { $0.gameNumber < $1.gameNumber }
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games.map(\.teamAFinalScore), [11, 11])
        XCTAssertEqual(games.map(\.teamBFinalScore), [0, 0])
        XCTAssertEqual(games.map { $0.points?.count ?? 0 }, [11, 11])
        XCTAssertTrue(games.allSatisfy { $0.completedAt != nil }, "completion dates are captured live")
        let names = Set((record.teamSides ?? []).map(\.displayName))
        XCTAssertEqual(names, ["Team A", "Team B"])
        XCTAssertEqual(PendingSyncStore(userDefaults: defaults).pendingMatchIDs, [record.id])
        // The snapshot is gone: a relaunch must not resurrect the finished match.
        XCTAssertNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil))
    }

    func testFinishIsIdempotentAndDoesNotSaveTwice() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 11)
        let first = try session.finish()
        let second = try session.finish()
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
        XCTAssertEqual(PendingSyncStore(userDefaults: defaults).pendingMatchIDs.count, 1)
    }

    func testMatchIsSavedTheMomentItEndsSoLeavingTheMatchOverScreenLosesNothing() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 11)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
        XCTAssertEqual(PendingSyncStore(userDefaults: defaults).pendingMatchIDs.count, 1)
    }

    func testUndoingTheMatchWinningPointUnsavesTheMatch() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 11)
        session.undo()
        XCTAssertFalse(session.isMatchOver)
        XCTAssertEqual(session.score(for: .teamA), 10)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
        XCTAssertEqual(PendingSyncStore(userDefaults: defaults).pendingMatchIDs, [])
        // And the match is live again after a relaunch.
        let relaunched = makeSession()
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertEqual(relaunched.score(for: .teamA), 10)
    }

    func testFinishBeforeTheMatchIsOverThrows() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        XCTAssertThrowsError(try session.finish())
    }

    func testDismissingAFinishedMatchLeavesTheSessionIdle() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 11)
        try session.dismissFinishedMatch()
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
    }

    func testAbandonSavesNothingAndClearsTheSnapshot() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfThree, firstServingTeam: .teamA)
        session.recordPoint(for: .teamA)
        session.abandon()
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
        XCTAssertNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil))
        XCTAssertEqual(PendingSyncStore(userDefaults: defaults).pendingMatchIDs, [])
        XCTAssertFalse(makeSession().resumeIfNeeded())
    }

    func testStartingANewMatchReplacesTheOldSnapshot() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        session.recordPoint(for: .teamA)
        session.abandon()
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamB)
        let relaunched = makeSession()
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertEqual(relaunched.servingTeam, .teamB)
        XCTAssertEqual(relaunched.score(for: .teamA), 0)
    }
}
