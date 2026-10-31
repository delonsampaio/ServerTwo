import XCTest
import SwiftData
@testable import PickleballKit

@MainActor
final class StandaloneMatchSessionTests: XCTestCase {
    private var suite = ""
    private var context: ModelContext!
    private var repository: MatchRepository!
    private var clock = Date(timeIntervalSince1970: 1_000)

    override func setUp() async throws {
        let suite = "StandaloneMatchSessionTests-\(UUID().uuidString)"
        self.suite = suite
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        repository = MatchRepository(modelContext: context)
    }

    private func makeSession() -> StandaloneMatchSession {
        StandaloneMatchSession(
            repository: repository,
            pendingSync: PendingSyncStore(suiteName: suite),
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

    func testTapCaptionExplainsWhatATapOnEachZoneDoes() {
        let doubles = makeSession()
        doubles.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        XCTAssertEqual(doubles.tapCaption(for: .teamA), "Tap to Score")
        // Server 2 is up first (0-0-2): the other team's tap is a full side out.
        XCTAssertEqual(doubles.tapCaption(for: .teamB), "Tap for Side Out")
        doubles.recordPoint(for: .teamB)               // side out: B serves, Server 1
        XCTAssertEqual(doubles.tapCaption(for: .teamA), "Tap for 2nd Server")

        let rally = makeSession()
        rally.start(configuration: GameConfiguration(scoringFormat: .rally(freeze: false)), format: .bestOfOne, firstServingTeam: .teamA)
        XCTAssertEqual(rally.tapCaption(for: .teamB), "Tap to Score")

        let singles = makeSession()
        singles.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        XCTAssertEqual(singles.tapCaption(for: .teamB), "Tap for Side Out")
    }

    func testSpokenSummaryIncludesGamesWonOnlyWhenTheFormatHasGames() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfThree, firstServingTeam: .teamA)
        XCTAssertEqual(session.spokenSummary(for: .teamA), "Team A, 0 points, serving, no games won")
        XCTAssertEqual(session.spokenSummary(for: .teamB), "Team B, 0 points, no games won")
        playOutGame(session, winner: .teamA)
        session.startNextGame()
        XCTAssertEqual(session.spokenSummary(for: .teamA), "Team A, 0 points, 1 game won")
        XCTAssertEqual(session.spokenSummary(for: .teamB), "Team B, 0 points, serving, no games won")
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
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs, [record.id])
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
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs.count, 1)
    }

    func testMatchIsSavedTheMomentItEndsSoLeavingTheMatchOverScreenLosesNothing() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 11)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs.count, 1)
    }

    func testUndoingTheMatchWinningPointUnsavesTheMatch() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 11)
        session.undo()
        XCTAssertFalse(session.isMatchOver)
        XCTAssertEqual(session.score(for: .teamA), 10)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs, [])
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
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs, [])
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

    // MARK: Initial service alternation, undo after save

    func testReceivingTeamWinningGameOneStillGivesTheOpponentOfTheFirstServerTheNextServe() {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfThree, firstServingTeam: .teamA)
        playOutGame(session, winner: .teamB)           // B wins game 1 although A served first
        XCTAssertEqual(session.lastCompletedGame?.winner, .teamB)
        XCTAssertEqual(session.lastCompletedGame?.nextServingTeam, .teamB, "opponent of A, not 'loser serves'")
        session.startNextGame()
        XCTAssertEqual(session.servingTeam, .teamB)

        playOutGame(session, winner: .teamA)           // A wins game 2 (B served first): 1-1
        XCTAssertEqual(session.lastCompletedGame?.winner, .teamA)
        session.startNextGame()
        XCTAssertEqual(session.servingTeam, .teamA, "game 3 starts with game 1's first server")
    }

    func testUndoingTheDecidingPointOfABestOfThreeRemovesTheRecordAndReplaySavesExactlyOne() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfThree, firstServingTeam: .teamA)
        playOutGame(session, winner: .teamA)
        session.startNextGame()
        playOutGame(session, winner: .teamA)
        XCTAssertTrue(session.isMatchOver)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)

        session.undo()
        XCTAssertFalse(session.isMatchOver)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs, [])

        playOutGame(session, winner: .teamA)
        XCTAssertTrue(session.isMatchOver)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs.count, 1)
    }

    func testFailedDeleteOnUndoIsRetriedAtTheNextSaveSoThereIsNeverASecondRecord() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 11)
        let original = try XCTUnwrap(try repository.fetchMatchHistory().first).id

        struct DeleteFailed: Error {}
        session.deleteMatchRecord = { _ in throw DeleteFailed() }
        session.undo()
        XCTAssertFalse(session.isMatchOver, "the undo still takes effect in the live match")
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1, "the stale record is still there")
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs, [original],
                       "and still queued: it is only dropped once it is really deleted")

        // The delete works again: replaying the deciding point replaces it.
        session.deleteMatchRecord = { [repository] in try repository!.deleteMatch($0) }
        tap(session, .teamA, times: 1)
        XCTAssertTrue(session.isMatchOver)
        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertNotEqual(history.first?.id, original)
        XCTAssertEqual(PendingSyncStore(suiteName: suite).pendingMatchIDs, [history[0].id])
    }

    func testPointCallbackRunsBeforeTheSnapshotIsWritten() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        var scoreSeenInCallback: Int?
        var snapshotScoreAtCallback: Int?
        session.recordPoint(for: .teamA) { _ in
            scoreSeenInCallback = session.score(for: .teamA)
            snapshotScoreAtCallback = try? self.repository
                .loadInProgressMatch(proUnlocked: true, demoPointCap: nil)?.match.currentGame.state.teamAScore
        }
        XCTAssertEqual(scoreSeenInCallback, 1, "the UI state is already updated for the haptic")
        XCTAssertEqual(snapshotScoreAtCallback, 0, "the slower snapshot write comes after the callback")
        XCTAssertEqual(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil)?.match.currentGame.state.teamAScore, 1)
    }

    func testDecidedMatchSnapshotIsNotWrittenSoAFailedFinalSaveResumesOnePointShort() throws {
        let session = makeSession()
        session.start(configuration: GameConfiguration(playMode: .singles), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 10)
        struct SaveFailed: Error {}
        session.saveFailureForTesting = SaveFailed()
        session.recordPoint(for: .teamA)
        XCTAssertTrue(session.isMatchOver)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
        // Killed now: the snapshot from before the deciding point is what's left.
        let relaunched = makeSession()
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertEqual(relaunched.score(for: .teamA), 10)
        XCTAssertFalse(relaunched.isMatchOver)
        // Back in the first session, Done retries the save and succeeds.
        session.saveFailureForTesting = nil
        try session.dismissFinishedMatch()
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
    }

    // MARK: Sync hooks (B1)

    private func finishMatch(_ session: StandaloneMatchSession) {
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        playOutGame(session, winner: .teamA)
    }

    func testThePendingIDIsQueuedBeforeTheSaveAndIsTheRecordsID() throws {
        let session = makeSession()
        let pending = PendingSyncStore(suiteName: suite)
        var pendingDuringSave: [UUID] = []
        session.beforeSaveForTesting = { pendingDuringSave = pending.pendingMatchIDs }
        finishMatch(session)
        let record = try XCTUnwrap(try repository.fetchMatchHistory().first)
        XCTAssertEqual(pendingDuringSave, [record.id], "marked pending before saveCompletedMatch ran")
        XCTAssertEqual(pending.pendingMatchIDs, [record.id])
    }

    func testAFailedSaveRemovesTheIDItQueuedBeforehand() throws {
        let session = makeSession()
        let pending = PendingSyncStore(suiteName: suite)
        session.saveFailureForTesting = NSError(domain: "x", code: 1)
        finishMatch(session)  // the automatic save at the deciding point fails
        XCTAssertEqual(pending.pendingMatchIDs, [], "no pending id without a record")
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
    }

    func testUndoableSavedMatchIDIsSetOnMatchOverAndClearedByUndoAndDone() throws {
        let session = makeSession()
        XCTAssertNil(session.undoableSavedMatchID)
        finishMatch(session)
        let id = try XCTUnwrap(session.undoableSavedMatchID)
        XCTAssertEqual(session.heldBackMatchIDs, [id])

        session.undo()
        XCTAssertNil(session.undoableSavedMatchID)

        playOutGame(session, winner: .teamA)
        XCTAssertNotNil(session.undoableSavedMatchID)
        try session.dismissFinishedMatch()
        XCTAssertNil(session.undoableSavedMatchID)
        XCTAssertTrue(session.heldBackMatchIDs.isEmpty)
    }

    func testDismissingFiresTheDoneCallbackOnlyAfterASuccessfulSave() throws {
        let session = makeSession()
        var fired = 0
        session.onFinishedMatchDismissed = { fired += 1 }
        finishMatch(session)
        try session.dismissFinishedMatch()
        XCTAssertEqual(fired, 1)
    }

    // MARK: Save failures (review gaps)

    private struct HookFailure: Error {}

    func testASaveThatThrowsBeforeStoringLeavesNothingAndNoPendingID() throws {
        let session = makeSession()
        let pending = PendingSyncStore(suiteName: suite)
        repository.beforeSaveHookForTesting = { throw HookFailure() }
        finishMatch(session)  // the automatic save at the deciding point throws

        XCTAssertNil(session.undoableSavedMatchID, "no record to point at")
        XCTAssertEqual(pending.pendingMatchIDs, [])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MatchRecord>()), 0, "the unsaved graph was rolled back")

        // Done retries and now stores exactly one match, queued once.
        repository.beforeSaveHookForTesting = nil
        try session.dismissFinishedMatch()
        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(pending.pendingMatchIDs, [history[0].id])
    }

    func testASaveThatThrowsAfterStoringKeepsTheStoredRecordAndDoesNotDuplicate() throws {
        let session = makeSession()
        let pending = PendingSyncStore(suiteName: suite)
        repository.afterSaveHookForTesting = { throw HookFailure() }
        finishMatch(session)

        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 1, "the record really was stored")
        XCTAssertEqual(session.undoableSavedMatchID, history[0].id)
        XCTAssertEqual(pending.pendingMatchIDs, [history[0].id])

        repository.afterSaveHookForTesting = nil
        try session.dismissFinishedMatch()
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1, "Done does not save the match a second time")
        XCTAssertEqual(pending.pendingMatchIDs, [history[0].id])
    }

    func testAbandonOnAnAlreadySavedMatchKeepsItQueuedAndTriggersSync() throws {
        let session = makeSession()
        let pending = PendingSyncStore(suiteName: suite)
        var fired = 0
        session.onFinishedMatchDismissed = { fired += 1 }
        finishMatch(session)
        let id = try XCTUnwrap(session.undoableSavedMatchID)

        session.abandon()

        XCTAssertEqual(fired, 1, "the pending match is handed to sync, not orphaned")
        XCTAssertEqual(pending.pendingMatchIDs, [id])
        XCTAssertNotNil(try repository.fetchMatchRecord(id: id))
        XCTAssertFalse(session.isActive)
    }

    func testAbandonMidMatchStillSavesNothing() throws {
        let session = makeSession()
        var fired = 0
        session.onFinishedMatchDismissed = { fired += 1 }
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 3)
        session.abandon()
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 0)
    }

    // MARK: Free-demo counter (B1 gate)

    private func makeCountingSession(_ counter: WatchLifetimeCounter) -> StandaloneMatchSession {
        StandaloneMatchSession(
            repository: repository,
            pendingSync: PendingSyncStore(suiteName: suite),
            lifetimeCounter: counter,
            now: { [unowned self] in
                self.clock.addTimeInterval(60)
                return self.clock
            }
        )
    }

    func testSavingAMatchCountsItOnce() throws {
        let counter = WatchLifetimeCounter(suiteName: suite)
        let session = makeCountingSession(counter)
        XCTAssertEqual(counter.count, 0)
        finishMatch(session)
        XCTAssertEqual(counter.count, 1)
        try session.dismissFinishedMatch()  // Done must not count it again
        XCTAssertEqual(counter.count, 1)
    }

    func testUndoingTheDecidingPointGivesTheMatchBackAndReplayingCountsAgain() throws {
        let counter = WatchLifetimeCounter(suiteName: suite)
        let session = makeCountingSession(counter)
        finishMatch(session)
        session.undo()
        XCTAssertEqual(counter.count, 0)
        playOutGame(session, winner: .teamA)
        XCTAssertEqual(counter.count, 1)
    }

    func testAFailedSaveDoesNotCount() throws {
        let counter = WatchLifetimeCounter(suiteName: suite)
        let session = makeCountingSession(counter)
        session.saveFailureForTesting = NSError(domain: "x", code: 1)
        finishMatch(session)
        XCTAssertEqual(counter.count, 0)
        session.saveFailureForTesting = nil
        try session.dismissFinishedMatch()
        XCTAssertEqual(counter.count, 1)
    }

    func testASaveThatThrowsAfterStoringStillCountsOnce() throws {
        let counter = WatchLifetimeCounter(suiteName: suite)
        let session = makeCountingSession(counter)
        repository.afterSaveHookForTesting = { throw HookFailure() }
        finishMatch(session)
        XCTAssertEqual(counter.count, 1)
        repository.afterSaveHookForTesting = nil
        try session.dismissFinishedMatch()
        XCTAssertEqual(counter.count, 1)
    }

    func testAbandoningAMatchInProgressNeverCounts() {
        let counter = WatchLifetimeCounter(suiteName: suite)
        let session = makeCountingSession(counter)
        session.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        tap(session, .teamA, times: 3)
        session.abandon()
        XCTAssertEqual(counter.count, 0)
    }

    // MARK: Stale snapshot after a recovered save

    func testDoneClearsTheSnapshotLeftByARecoveredSave() throws {
        let session = makeSession()
        repository.afterSaveHookForTesting = { throw HookFailure() }
        finishMatch(session)
        XCTAssertNotNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil), "precondition: the stale snapshot is on disk")

        repository.afterSaveHookForTesting = nil
        try session.dismissFinishedMatch()

        XCTAssertNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil))
    }

    func testAbandonClearsTheSnapshotLeftByARecoveredSave() throws {
        let session = makeSession()
        repository.afterSaveHookForTesting = { throw HookFailure() }
        finishMatch(session)
        repository.afterSaveHookForTesting = nil
        session.abandon()
        XCTAssertNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil))
    }

    func testARelaunchAfterARecoveredSaveDoesNotResumeTheSavedMatchOrSaveItTwice() throws {
        let counter = WatchLifetimeCounter(suiteName: suite)
        let first = makeCountingSession(counter)
        repository.afterSaveHookForTesting = { throw HookFailure() }
        finishMatch(first)  // stored and counted, snapshot left behind; then the app dies
        repository.afterSaveHookForTesting = nil
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
        XCTAssertEqual(counter.count, 1)

        let relaunched = makeCountingSession(counter)
        XCTAssertFalse(relaunched.resumeIfNeeded(), "the saved match must not come back")
        XCTAssertFalse(relaunched.isActive)
        XCTAssertNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil), "and the stale snapshot is gone")
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1, "no second record")
        XCTAssertEqual(counter.count, 1, "not counted again")
    }

    func testARelaunchStillResumesAnUnfinishedMatchWithTheSameRecordsAround() throws {
        // A saved match from earlier must not stop a genuinely unfinished one
        // (different start time) from resuming.
        let first = makeSession()
        finishMatch(first)
        try first.dismissFinishedMatch()
        let live = makeSession()
        live.start(configuration: GameConfiguration(), format: .bestOfOne, firstServingTeam: .teamA)
        tap(live, .teamA, times: 3)

        let relaunched = makeSession()
        XCTAssertTrue(relaunched.resumeIfNeeded())
        XCTAssertEqual(relaunched.score(for: .teamA), 3)
    }
}
