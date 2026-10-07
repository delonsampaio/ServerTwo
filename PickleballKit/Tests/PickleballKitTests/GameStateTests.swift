import XCTest
@testable import PickleballKit

final class GameStateTests: XCTestCase {
    func testInitAndAccessors() {
        let state = GameState(
            teamAScore: 3,
            teamBScore: 5,
            servingTeam: .teamA,
            serverNumber: .two,
            teamATimeoutsRemaining: 2,
            teamBTimeoutsRemaining: 1,
            hasSideSwitched: false,
            lastPointWonWhileServing: true
        )
        XCTAssertEqual(state.score(for: .teamA), 3)
        XCTAssertEqual(state.score(for: .teamB), 5)
        XCTAssertEqual(state.timeoutsRemaining(for: .teamA), 2)
        XCTAssertEqual(state.timeoutsRemaining(for: .teamB), 1)
    }

    func testEquatable() {
        let a = GameState(
            teamAScore: 0, teamBScore: 0, servingTeam: .teamA,
            serverNumber: .two, teamATimeoutsRemaining: 2,
            teamBTimeoutsRemaining: 2, hasSideSwitched: false,
            lastPointWonWhileServing: true
        )
        var b = a
        XCTAssertEqual(a, b)
        b.teamAScore = 1
        XCTAssertNotEqual(a, b)
    }
}
