import XCTest
@testable import ServerTwo
import PickleballKit

@MainActor
final class EditMatchPlayersValidationTests: XCTestCase {
    private func entry(_ name: String, _ player: SavedPlayer? = nil) -> PlayerSlotEntry {
        PlayerSlotEntry(name: name, savedPlayerID: player?.id)
    }

    func testSlotCountFollowsTheRulesButNeverHidesAnExistingPlayer() {
        XCTAssertEqual(EditMatchPlayersValidation.slotCount(isDoubles: true, currentPlayerCount: 0), 2)
        XCTAssertEqual(EditMatchPlayersValidation.slotCount(isDoubles: false, currentPlayerCount: 1), 1)
        XCTAssertEqual(EditMatchPlayersValidation.slotCount(isDoubles: false, currentPlayerCount: 0), 1)
        XCTAssertEqual(EditMatchPlayersValidation.slotCount(isDoubles: false, currentPlayerCount: 2), 2)
        XCTAssertEqual(EditMatchPlayersValidation.slotCount(isDoubles: nil, currentPlayerCount: 2), 2)
        XCTAssertEqual(EditMatchPlayersValidation.slotCount(isDoubles: nil, currentPlayerCount: 0), 2, "undecodable rules count as doubles")
        XCTAssertEqual(EditMatchPlayersValidation.slotCount(isDoubles: true, currentPlayerCount: 5), 2)
    }

    func testCurrentEntriesPreferLinkedPlayersThenSplitALegacyName() {
        let linked = [PlayerSlotEntry(name: "Mike", savedPlayerID: UUID())]
        XCTAssertEqual(EditMatchPlayersValidation.currentEntries(linked: linked, displayName: "Other", team: .teamA), linked)
        XCTAssertEqual(
            EditMatchPlayersValidation.currentEntries(linked: [], displayName: "Mike & Bob", team: .teamA).map(\.name),
            ["Mike", "Bob"]
        )
        XCTAssertEqual(
            EditMatchPlayersValidation.currentEntries(linked: [], displayName: "Andy", team: .teamB).map(\.name),
            ["Andy"], "only the exact \" & \" splits, so Andy stays whole"
        )
    }

    func testThePlaceholderNameIsNotACurrentPlayer() {
        XCTAssertTrue(EditMatchPlayersValidation.currentEntries(linked: [], displayName: "Team A", team: .teamA).isEmpty)
        XCTAssertTrue(EditMatchPlayersValidation.currentEntries(linked: [], displayName: "Team B", team: .teamB).isEmpty)
        // "Team B" is only a placeholder on team B's own side.
        XCTAssertEqual(EditMatchPlayersValidation.currentEntries(linked: [], displayName: "Team B", team: .teamA).count, 1)
    }

    func testSlotsArePaddedWithBlanksOrCut() {
        let one = [PlayerSlotEntry(name: "Mike")]
        XCTAssertEqual(EditMatchPlayersValidation.slots(one, count: 2).map(\.name), ["Mike", ""])
        XCTAssertEqual(EditMatchPlayersValidation.slots([], count: 1).map(\.name), [""])
        XCTAssertEqual(EditMatchPlayersValidation.slots(one + one, count: 1).map(\.name), ["Mike"])
    }

    func testBlanksAreNeverAProblem() {
        XCTAssertNil(EditMatchPlayersValidation.problem(teamA: [entry(""), entry("  ")], teamB: [entry("")], savedPlayers: []))
    }

    func testTheSamePlayerTwiceIsAProblemWithAOneLineReason() {
        let mike = SavedPlayer(name: "Mike")
        let reason = EditMatchPlayersValidation.problem(
            teamA: [entry("Mike", mike)], teamB: [entry("Mike", mike)], savedPlayers: [mike]
        )
        XCTAssertEqual(reason, "Mike is listed more than once.")
        XCTAssertFalse(reason?.contains("\n") ?? true)
    }

    func testATypedNameMatchingASavedPlayerCaseInsensitivelyIsADuplicate() {
        let mike = SavedPlayer(name: "Mike")
        XCTAssertEqual(
            EditMatchPlayersValidation.problem(teamA: [entry("Mike", mike), entry("")], teamB: [entry(" mike ")], savedPlayers: [mike]),
            "mike is listed more than once."
        )
        XCTAssertNotNil(EditMatchPlayersValidation.problem(teamA: [entry("Zed")], teamB: [entry("zed")], savedPlayers: []))
    }

    func testDifferentPeopleAreNotAProblem() {
        let mike = SavedPlayer(name: "Mike")
        let bob = SavedPlayer(name: "Bob")
        XCTAssertNil(EditMatchPlayersValidation.problem(
            teamA: [entry("Mike", mike), entry("Zed")], teamB: [entry("Bob", bob), entry("Quinn")], savedPlayers: [mike, bob]
        ))
    }

    func testTwoDifferentSavedPlayersSharingANameAreAllowedWhenEachWasPicked() {
        let mike1 = SavedPlayer(name: "Mike")
        let mike2 = SavedPlayer(name: "Mike")
        XCTAssertNil(EditMatchPlayersValidation.problem(
            teamA: [entry("Mike", mike1)], teamB: [entry("Mike", mike2)], savedPlayers: [mike1, mike2]
        ))
    }

    func testTypedDelonWithTrailingSpaceDuplicatesPickedDelon() {
        let delon = SavedPlayer(name: "Delon")
        XCTAssertEqual(
            EditMatchPlayersValidation.problem(teamA: [entry("Delon", delon)], teamB: [entry("delon ")], savedPlayers: [delon]),
            "delon is listed more than once."
        )
    }

    func testAPlaceholderSideOpensWithBlankSlotsSoSaveCannotCreateAPlayerNamedTeamA() {
        let current = EditMatchPlayersValidation.currentEntries(linked: [], displayName: "Team A", team: .teamA)
        let slots = EditMatchPlayersValidation.slots(current, count: 2)
        XCTAssertTrue(slots.allSatisfy(\.isBlank))
    }
}
