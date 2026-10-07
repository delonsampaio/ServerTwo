import XCTest
@testable import PickleballKit

final class PointEventDerivationTests: XCTestCase {
    func testDerivePointEventsSkipsNonScoringTransitions() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false))
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.recordPoint(for: .teamA)
        game.requestTimeout(for: .teamB)
        game.recordPoint(for: .teamB)

        let events = derivePointEvents(history: game.history, finalState: game.state)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], DerivedPointEvent(sequenceNumber: 1, scoringTeam: .teamA, teamAScoreAfter: 1, teamBScoreAfter: 0))
        XCTAssertEqual(events[1], DerivedPointEvent(sequenceNumber: 2, scoringTeam: .teamB, teamAScoreAfter: 1, teamBScoreAfter: 1))
    }

    func testDerivePointEventsWithNoHistoryReturnsEmpty() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        let events = derivePointEvents(history: game.history, finalState: game.state)
        XCTAssertTrue(events.isEmpty)
    }
}
