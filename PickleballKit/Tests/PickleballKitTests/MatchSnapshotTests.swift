import XCTest
@testable import PickleballKit

final class MatchSnapshotTests: XCTestCase {
    func testMatchSnapshotRoundTripPreservesStateAndUndoCapability() throws {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let original = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { original.recordPoint(for: .teamA) }
        original.recordPoint(for: .teamB)
        original.recordPoint(for: .teamB)

        let data = try JSONEncoder().encode(original.snapshot(startedAt: Date()))
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        let resumed = PickleballMatch(resuming: decoded, proUnlocked: true, demoPointCap: nil)

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
        let data = try JSONEncoder().encode(original.snapshot(startedAt: Date()))
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        let resumed = PickleballMatch(resuming: decoded, proUnlocked: false, demoPointCap: 5)
        XCTAssertEqual(resumed.currentGame.state.teamAScore, 0)
        XCTAssertFalse(resumed.currentGame.proUnlocked)
        XCTAssertEqual(resumed.currentGame.demoPointCap, 5)
    }

    func testResumedMatchPreservesStartedAt() throws {
        let original = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        let startedAt = Date(timeIntervalSince1970: 12345)
        let data = try JSONEncoder().encode(original.snapshot(startedAt: startedAt))
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        XCTAssertEqual(decoded.startedAt, startedAt)
    }

    func testResumedMatchUsesCallerSuppliedEntitlementNotTheSnapshottedOne() throws {
        // The snapshot was taken while locked (proUnlocked: false); resuming
        // with proUnlocked: true (e.g. the user purchased while the app was
        // closed) must reflect the live entitlement, not the stale one.
        let original = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        let data = try JSONEncoder().encode(original.snapshot(startedAt: Date()))
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        let resumed = PickleballMatch(resuming: decoded, proUnlocked: true, demoPointCap: nil)
        XCTAssertTrue(resumed.currentGame.proUnlocked)
        XCTAssertNil(resumed.currentGame.demoPointCap)
    }

    func testUndoAfterResumingOnTheMatchDecidingGameCorrectlyReversesTheWinCount() throws {
        // Reproduces the exact scenario a real app hits: autosave an
        // in-progress snapshot after every point (per the spec's crash
        // recovery requirement), including the match-deciding point itself.
        // Before this fix, resuming from that snapshot made undo() revert
        // only the score, leaving the match permanently stuck "over".
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let original = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { original.recordPoint(for: .teamA) }
        XCTAssertTrue(original.isMatchOver)

        let data = try JSONEncoder().encode(original.snapshot(startedAt: Date()))
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        let resumed = PickleballMatch(resuming: decoded, proUnlocked: true, demoPointCap: nil)

        XCTAssertTrue(resumed.isMatchOver)
        XCTAssertEqual(resumed.gamesWon(for: .teamA), 1)
        XCTAssertEqual(resumed.completedGames.count, 1)

        resumed.undo()

        XCTAssertFalse(resumed.isMatchOver)
        XCTAssertEqual(resumed.gamesWon(for: .teamA), 0)
        XCTAssertEqual(resumed.completedGames.count, 0)
        XCTAssertEqual(resumed.currentGame.state.teamAScore, 10)
        XCTAssertFalse(resumed.currentGame.isGameOver)

        // The match must be genuinely playable again, not permanently stuck.
        resumed.recordPoint(for: .teamA)
        XCTAssertTrue(resumed.isMatchOver)
        XCTAssertEqual(resumed.gamesWon(for: .teamA), 1)
    }
}
