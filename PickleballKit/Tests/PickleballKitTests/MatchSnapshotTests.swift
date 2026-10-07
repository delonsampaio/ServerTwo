import XCTest
@testable import PickleballKit

final class MatchSnapshotTests: XCTestCase {
    func testMatchSnapshotRoundTripPreservesStateAndUndoCapability() throws {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let original = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { original.recordPoint(for: .teamA) }
        original.recordPoint(for: .teamB)
        original.recordPoint(for: .teamB)

        let data = try JSONEncoder().encode(original.snapshot)
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        let resumed = PickleballMatch(resuming: decoded)

        // Game 2: teamA serves first (won game 1) at Server 2. teamB's first
        // recordPoint is a full side-out (no score, serve passes to teamB);
        // teamB's second recordPoint is then a real score as the new server.
        XCTAssertEqual(resumed.completedGames.count, 1)
        XCTAssertEqual(resumed.gamesWon(for: .teamA), 1)
        XCTAssertEqual(resumed.currentGame.state.teamBScore, 1)
        XCTAssertTrue(resumed.currentGame.canUndo)
        resumed.undo()
        XCTAssertEqual(resumed.currentGame.state.teamBScore, 0)
    }

    func testMatchSnapshotRoundTripOfFreshMatch() throws {
        let original = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        let data = try JSONEncoder().encode(original.snapshot)
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        let resumed = PickleballMatch(resuming: decoded)
        XCTAssertEqual(resumed.currentGame.state.teamAScore, 0)
        XCTAssertFalse(resumed.currentGame.proUnlocked)
        XCTAssertEqual(resumed.currentGame.demoPointCap, 5)
    }
}
