import XCTest
@testable import PickleballKit

final class PickleballGameRehydrationTests: XCTestCase {
    func testRehydratedGameRestoresExactStateAndUndoCapability() {
        let original = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        original.recordPoint(for: .teamA)
        original.recordPoint(for: .teamA)

        let resumed = PickleballGame(
            configuration: original.configuration,
            state: original.state,
            history: original.history,
            proUnlocked: original.proUnlocked,
            demoPointCap: original.demoPointCap
        )

        XCTAssertEqual(resumed.state, original.state)
        XCTAssertTrue(resumed.canUndo)
        resumed.undo()
        XCTAssertEqual(resumed.state.teamAScore, 1)
        resumed.undo()
        XCTAssertEqual(resumed.state.teamAScore, 0)
        XCTAssertFalse(resumed.canUndo)
    }

    func testRehydratedGameWithEmptyHistoryCannotUndo() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        let resumed = PickleballGame(configuration: game.configuration, state: game.state, history: [], proUnlocked: true, demoPointCap: nil)
        XCTAssertFalse(resumed.canUndo)
    }
}
