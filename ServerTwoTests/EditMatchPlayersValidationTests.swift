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
        XCTAssertEqual(reason, "Mike is listed more than once. Add an initial to tell them apart, for example Mike S.")
        XCTAssertFalse(reason?.contains("\n") ?? true)
    }

    func testATypedNameMatchingASavedPlayerCaseInsensitivelyIsADuplicate() {
        let mike = SavedPlayer(name: "Mike")
        XCTAssertEqual(
            EditMatchPlayersValidation.problem(teamA: [entry("Mike", mike), entry("")], teamB: [entry(" mike ")], savedPlayers: [mike]),
            "mike is listed more than once. Add an initial to tell them apart, for example Mike S."
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
            "delon is listed more than once. Add an initial to tell them apart, for example Mike S."
        )
    }

    func testAPlaceholderSideOpensWithBlankSlotsSoSaveCannotCreateAPlayerNamedTeamA() {
        let current = EditMatchPlayersValidation.currentEntries(linked: [], displayName: "Team A", team: .teamA)
        let slots = EditMatchPlayersValidation.slots(current, count: 2)
        XCTAssertTrue(slots.allSatisfy(\.isBlank))
    }

    // MARK: hasChanges

    func testHasChangesIsFalseWhenNothingWasTouched() {
        let id = UUID()
        let a = [PlayerSlotEntry(name: "Mike", savedPlayerID: id), entry("")]
        let b = [entry("Bob"), entry("")]
        XCTAssertFalse(EditMatchPlayersValidation.hasChanges(initialTeamA: a, initialTeamB: b, teamA: a, teamB: b))
    }

    func testHasChangesIsTrueForOneChangedName() {
        let a = [entry("Mike"), entry("")]
        let b = [entry("Bob"), entry("")]
        XCTAssertTrue(EditMatchPlayersValidation.hasChanges(
            initialTeamA: a, initialTeamB: b, teamA: [entry("Mike"), entry("")], teamB: [entry("Rob"), entry("")]
        ))
    }

    func testHasChangesIgnoresCaseAndWhitespaceOnlyEdits() {
        let a = [entry("Mike"), entry("")]
        let b = [entry("Bob"), entry("")]
        XCTAssertFalse(EditMatchPlayersValidation.hasChanges(
            initialTeamA: a, initialTeamB: b, teamA: [entry(" mike "), entry("  ")], teamB: [entry("BOB"), entry("")]
        ))
    }

    func testHasChangesIsTrueWhenABlankSlotIsFilled() {
        let a = [entry("Mike"), entry("")]
        XCTAssertTrue(EditMatchPlayersValidation.hasChanges(
            initialTeamA: a, initialTeamB: [entry("")], teamA: [entry("Mike"), entry("Zed")], teamB: [entry("")]
        ))
    }

    func testHasChangesIsTrueWhenAFilledSlotIsBlanked() {
        let a = [entry("Mike"), entry("Zed")]
        XCTAssertTrue(EditMatchPlayersValidation.hasChanges(
            initialTeamA: a, initialTeamB: [entry("")], teamA: [entry("Mike"), entry("")], teamB: [entry("")]
        ))
    }

    func testHasChangesIsTrueWhenTheTwoTeamsSwapPlayers() {
        let a = [entry("Mike")]
        let b = [entry("Bob")]
        XCTAssertTrue(EditMatchPlayersValidation.hasChanges(initialTeamA: a, initialTeamB: b, teamA: b, teamB: a))
    }

    func testHasChangesIsTrueWhenAPickedPlayerChangesButTheNameTextDoesNot() {
        let mike1 = SavedPlayer(name: "Mike")
        let mike2 = SavedPlayer(name: "Mike")
        XCTAssertTrue(EditMatchPlayersValidation.hasChanges(
            initialTeamA: [entry("Mike", mike1)], initialTeamB: [entry("")],
            teamA: [entry("Mike", mike2)], teamB: [entry("")]
        ))
        XCTAssertTrue(EditMatchPlayersValidation.hasChanges(
            initialTeamA: [entry("Mike", mike1)], initialTeamB: [entry("")],
            teamA: [entry("Mike")], teamB: [entry("")]
        ), "dropping the picked id (re-linking by typing) is a change too")
    }
}
