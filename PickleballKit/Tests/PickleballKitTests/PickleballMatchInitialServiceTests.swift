import XCTest
@testable import PickleballKit

/// Rule 21.F.2: teams change ends AND initial service for the next game, so the
/// first server alternates every game and never depends on who won.
final class PickleballMatchInitialServiceTests: XCTestCase {
    private func makeMatch(
        _ format: MatchFormat = .bestOfThree,
        first: Team = .teamA,
        config: GameConfiguration = GameConfiguration()
    ) -> PickleballMatch {
        PickleballMatch(configuration: config, matchFormat: format, firstServingTeam: first, proUnlocked: true, demoPointCap: nil)
    }

    func testInitialServiceAlternatesAcrossABestOfThree() {
        let match = makeMatch(first: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA)

        playOutGame(match, winner: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "the other team serves first in game 2")
        XCTAssertEqual(match.currentGame.state.servingTeam, .teamB)

        playOutGame(match, winner: .teamB)   // 1-1
        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA, "game 3 starts with game 1's first server")
    }

    func testStartingWithTeamBAlternatesTheSameWay() {
        let match = makeMatch(first: .teamB)
        playOutGame(match, winner: .teamB)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA)
        playOutGame(match, winner: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB)
    }

    func testWhoWonThePreviousGameDoesNotDecideTheNextFirstServer() {
        for winner in Team.allCases {
            let match = makeMatch(first: .teamA)
            playOutGame(match, winner: winner)
            XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "game 1 won by \(winner)")
        }
    }

    func testABestOfFiveAlternatesEveryGame() {
        let match = makeMatch(.bestOfFive, first: .teamA)
        let winners: [Team] = [.teamA, .teamB, .teamA, .teamB]
        let expectedFirst: [Team] = [.teamB, .teamA, .teamB, .teamA]
        for (winner, expected) in zip(winners, expectedFirst) {
            playOutGame(match, winner: winner)
            XCTAssertFalse(match.isMatchOver)
            XCTAssertEqual(match.currentGame.initialServingTeam, expected)
        }
    }

    func testSinglesAndRallyScoringAlternateToo() {
        let configs = [
            GameConfiguration(playMode: .singles, scoringFormat: .sideOut),
            GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: false)),
            GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: true)),
        ]
        for config in configs {
            for winner in Team.allCases {
                let match = makeMatch(first: .teamA, config: config)
                playOutGame(match, winner: winner)
                XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "\(config.scoringFormat) \(config.playMode), game 1 won by \(winner)")
            }
        }
    }

    func testInitialServingTeamSurvivesMovesCorrectionAndUndo() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        XCTAssertEqual(game.initialServingTeam, .teamA)

        game.recordPoint(for: .teamB)   // doubles 0-0-2: B wins the rally, a full side-out
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.initialServingTeam, .teamA, "the first history entry is the state before the first move")

        game.correctScores(teamA: 5, teamB: 3)
        XCTAssertEqual(game.initialServingTeam, .teamA)

        game.undo()
        game.undo()
        XCTAssertFalse(game.canUndo)
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.initialServingTeam, .teamA, "with every move undone the state itself is the initial state")
    }

    func testACorrectionThatEndsAGameGivesTheNextGameToTheFirstServersOpponent() {
        for (a, b) in [(11, 9), (9, 11)] {
            let match = makeMatch(first: .teamA)
            match.correctScores(teamA: a, teamB: b)
            XCTAssertEqual(match.completedGames.count, 1, "\(a)-\(b)")
            XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "\(a)-\(b): not the winner")
        }
    }

    func testFlippingTheWinnerOfADecidedGameStillAlternates() {
        // Engine-only path (the UI disables scoring once the match is over).
        let match = makeMatch(first: .teamA)
        playOutGame(match, winner: .teamA)    // game 1; game 2 starts with B serving
        playOutGame(match, winner: .teamA)    // game 2: A wins, match over 2-0
        XCTAssertTrue(match.isMatchOver)

        match.correctScores(teamA: 0, teamB: 11)   // game 2 now belongs to B: 1-1, game 3 created

        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.completedGames.count, 2)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA, "game 2's first server was B, so game 3 starts with A")
    }

    func testUndoingAGameEndingPointAndReplayingGivesTheSameNextFirstServer() {
        let match = makeMatch(first: .teamA)
        playOutGame(match, winner: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB)

        match.undo()   // reopens game 1 one point before the end
        XCTAssertTrue(match.completedGames.isEmpty)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamA)

        playOutGame(match, winner: .teamA)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB)
    }

    func testAResumedMatchKeepsAlternating() {
        let match = makeMatch(first: .teamA)
        playOutGame(match, winner: .teamA)
        let snapshot = match.snapshot(startedAt: Date(timeIntervalSince1970: 0))

        let resumed = PickleballMatch(resuming: snapshot, proUnlocked: true, demoPointCap: nil)
        XCTAssertEqual(resumed.currentGame.initialServingTeam, .teamB)

        playOutGame(resumed, winner: .teamB)   // 1-1
        XCTAssertEqual(resumed.currentGame.initialServingTeam, .teamA)
    }

    func testAResumedMidGameMatchKeepsTheGamesFirstServer() {
        let match = makeMatch(first: .teamA)
        playOutGame(match, winner: .teamA)     // game 2 starts with B serving
        match.recordPoint(for: .teamA)         // A is receiving: a side-out, serve passes to A
        match.recordPoint(for: .teamA)         // A is now serving: a real score
        let snapshot = match.snapshot(startedAt: Date(timeIntervalSince1970: 0))

        let resumed = PickleballMatch(resuming: snapshot, proUnlocked: true, demoPointCap: nil)
        XCTAssertEqual(resumed.currentGame.state.servingTeam, .teamA)
        // They differ on purpose: the persisted history, not the live state, carries the first server.
        XCTAssertEqual(resumed.currentGame.initialServingTeam, .teamB)

        playOutGame(resumed, winner: .teamB)   // 1-1
        XCTAssertEqual(resumed.currentGame.initialServingTeam, .teamA, "game 3 starts with game 1's first server")
    }

    func testAMatchSavedUnderTheOldRuleFollowsTheStoredFirstServerOfTheCurrentGame() {
        // Old build: game 1 started with A and A won; game 2 started with the
        // winner (A) serving. Games created after the upgrade derive their first
        // server from the stored first server of the game being replaced, so
        // game 3 starts with B. (Best of five so that A winning game 2 does not
        // end the match; the old winner-serves rule would give A here.)
        let config = GameConfiguration()
        let game1 = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { game1.recordPoint(for: .teamA) }
        let game2 = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        let match = PickleballMatch(
            configuration: config, matchFormat: .bestOfFive,
            completedGames: [game1], currentGame: game2,
            gamesWon: [.teamA: 1, .teamB: 0], currentGameIsCounted: false
        )

        playOutGame(match, winner: .teamA)   // A serves first and wins game 2: 2-0
        XCTAssertFalse(match.isMatchOver)
        XCTAssertEqual(match.currentGame.initialServingTeam, .teamB, "game 2 began with A serving, so game 3 begins with B (the old rule would give A)")
    }
}
