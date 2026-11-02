import XCTest
@testable import PickleballKit

final class WatchMatchPlayersNameVariantsTests: XCTestCase {
    private func ref(_ name: String) -> SyncedPlayerRef {
        SyncedPlayerRef(savedPlayerID: UUID(), name: name)
    }

    func testDoublesVariantsGoFromFullNamesToInitialsToFirstNames() {
        let players = WatchMatchPlayers(teamA: [ref("Delon Sampaio"), ref("Mike Ross")])
        XCTAssertEqual(
            players.teamNameVariants(for: .teamA),
            ["Delon Sampaio & Mike Ross", "Delon S. & Mike R.", "Delon & Mike"]
        )
    }

    func testSingleWordNamesHaveNothingToShorten() {
        let players = WatchMatchPlayers(teamA: [ref("Mike"), ref("Sarah")])
        XCTAssertEqual(players.teamNameVariants(for: .teamA), ["Mike & Sarah"])
    }

    func testOnlyTheLongNameIsShortened() {
        let players = WatchMatchPlayers(teamA: [ref("Delon Sampaio"), ref("Sarah")])
        XCTAssertEqual(
            players.teamNameVariants(for: .teamA),
            ["Delon Sampaio & Sarah", "Delon S. & Sarah", "Delon & Sarah"]
        )
    }

    func testMiddleNamesAreDroppedAndTheInitialIsUppercased() {
        let players = WatchMatchPlayers(teamA: [ref("mary jane van der berg")])
        XCTAssertEqual(
            players.teamNameVariants(for: .teamA),
            ["mary jane van der berg", "mary B.", "mary"]
        )
    }

    func testFirstNamesAloneAreSkippedWhenTheyWouldLookTheSame() {
        let players = WatchMatchPlayers(teamA: [ref("Mike Ross"), ref("Mike Stone")])
        XCTAssertEqual(
            players.teamNameVariants(for: .teamA),
            ["Mike Ross & Mike Stone", "Mike R. & Mike S."]
        )
    }

    func testEmptySideKeepsItsPlaceholder() {
        XCTAssertEqual(WatchMatchPlayers.empty.teamNameVariants(for: .teamB), ["Team B"])
    }

    func testFirstVariantIsAlwaysTheFullTeamName() {
        let players = WatchMatchPlayers(teamB: [ref("Ana Souza"), ref("Bo Lee")])
        XCTAssertEqual(players.teamNameVariants(for: .teamB).first, players.teamName(for: .teamB))
    }

    func testWinnerHeadlineAgreesWithOneOrTwoPlayers() {
        let players = WatchMatchPlayers(
            teamA: [ref("Delon"), ref("Sarah")], teamB: [ref("Priya")]
        )
        XCTAssertEqual(players.winnerHeadline(for: .teamA), "Delon & Sarah win")
        XCTAssertEqual(players.winnerHeadline(for: .teamB), "Priya wins")
    }

    func testWinnerHeadlineForAnEmptySideUsesItsPlaceholder() {
        XCTAssertEqual(WatchMatchPlayers.empty.winnerHeadline(for: .teamA), "Team A wins")
    }
}
