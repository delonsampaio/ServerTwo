import XCTest
@testable import PickleballKit

final class PickleballMatchRehydrationTests: XCTestCase {
    func testRehydratedMatchPreservesCompletedGamesAndCurrentGame() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let original = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { original.recordPoint(for: .teamA) }
        original.recordPoint(for: .teamA)

        let resumed = PickleballMatch(
            configuration: original.configuration,
            matchFormat: original.matchFormat,
            completedGames: original.completedGames,
            currentGame: original.currentGame,
            gamesWon: [.teamA: original.gamesWon(for: .teamA), .teamB: original.gamesWon(for: .teamB)],
            currentGameIsCounted: false
        )

        // Game 2 starts with teamB serving at Server 2 (Rule 21.F.2: the
        // other team serves first, not the winner; brand new game rule);
        // teamA's recordPoint call is a full side-out, not a score, under the
        // default side-out scoring format.
        XCTAssertEqual(resumed.completedGames.count, 1)
        XCTAssertEqual(resumed.gamesWon(for: .teamA), 1)
        XCTAssertEqual(resumed.currentGame.state.teamAScore, 0)
        XCTAssertEqual(resumed.currentGame.state.teamBScore, 0)
        XCTAssertEqual(resumed.currentGame.state.servingTeam, .teamA)
        XCTAssertTrue(resumed.currentGame.canUndo)
        resumed.undo()
        XCTAssertEqual(resumed.currentGame.state.servingTeam, .teamB)
    }
}
