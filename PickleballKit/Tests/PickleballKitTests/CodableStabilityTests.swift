import XCTest
@testable import PickleballKit

final class CodableStabilityTests: XCTestCase {
    func testScoringFormatRallyRoundTrips() throws {
        let original = ScoringFormat.rally(freeze: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScoringFormat.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testScoringFormatSideOutRoundTrips() throws {
        let data = try JSONEncoder().encode(ScoringFormat.sideOut)
        let decoded = try JSONDecoder().decode(ScoringFormat.self, from: data)
        XCTAssertEqual(decoded, .sideOut)
    }

    func testScoringFormatHasStableExplicitWireFormat() throws {
        let data = try JSONEncoder().encode(ScoringFormat.rally(freeze: true))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\""))
        XCTAssertTrue(json.contains("\"rally\""))
        XCTAssertTrue(json.contains("\"freeze\""))
    }

    func testGameConfigurationRoundTrips() throws {
        let original = GameConfiguration(
            playMode: .singles,
            scoringFormat: .rally(freeze: true),
            winningScore: .fifteen,
            winByTwo: false,
            timeoutsPerTeam: 1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameConfiguration.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testGameStateRoundTrips() throws {
        let original = GameState(
            teamAScore: 4,
            teamBScore: 7,
            servingTeam: .teamB,
            serverNumber: .two,
            teamATimeoutsRemaining: 1,
            teamBTimeoutsRemaining: 0,
            hasSideSwitched: true,
            lastPointWonWhileServing: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
