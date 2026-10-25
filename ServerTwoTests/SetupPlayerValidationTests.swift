import XCTest
@testable import ServerTwo
import PickleballKit

@MainActor
final class SetupPlayerValidationTests: XCTestCase {
    private func entry(_ name: String, _ player: SavedPlayer? = nil) -> PlayerSlotEntry {
        PlayerSlotEntry(name: name, savedPlayerID: player?.id)
    }

    private func duplicate(
        a: [PlayerSlotEntry], b: [PlayerSlotEntry], doubles: Bool = true, saved: [SavedPlayer] = []
    ) -> String? {
        SetupPlayerValidation.duplicateName(teamA: a, teamB: b, isDoubles: doubles, among: saved)
    }

    func testTheSameNameOnBothTeamsIsADuplicate() {
        XCTAssertEqual(duplicate(a: [entry("Mike"), entry("")], b: [entry("Mike"), entry("")]), "Mike")
    }

    func testTheSameNameTwiceOnOneTeamIsADuplicate() {
        XCTAssertEqual(duplicate(a: [entry("Mike"), entry("Mike")], b: [entry("Zed"), entry("")]), "Mike")
    }

    func testCaseAndWhitespaceDifferencesStillCount() {
        XCTAssertEqual(duplicate(a: [entry("Mike")], b: [entry("mike ")]), "mike")
        XCTAssertEqual(duplicate(a: [entry("  MIKE")], b: [entry("Mike")]), "Mike", "reports the later entry, as typed")
    }

    func testBlankSlotsNeverConflict() {
        XCTAssertNil(duplicate(a: [entry(""), entry("  ")], b: [entry(""), entry("\n")]))
    }

    func testSinglesIgnoresThePlayerTwoSlots() {
        XCTAssertNil(duplicate(a: [entry("Mike"), entry("Zed")], b: [entry("Bob"), entry("Zed")], doubles: false))
        XCTAssertNil(duplicate(a: [entry("Mike"), entry("Mike")], b: [entry("Bob"), entry("")], doubles: false))
        XCTAssertEqual(duplicate(a: [entry("Mike"), entry("")], b: [entry("mike"), entry("")], doubles: false), "mike")
    }

    func testDoublesLooksAtAllFourSlots() {
        XCTAssertEqual(duplicate(a: [entry("Mike"), entry("Zed")], b: [entry("Bob"), entry("zed")]), "zed")
    }

    func testTwoDifferentSavedPlayersSharingANameAreAllowedWhenEachWasPicked() {
        let mike1 = SavedPlayer(name: "Mike")
        let mike2 = SavedPlayer(name: "Mike")
        XCTAssertNil(duplicate(a: [entry("Mike", mike1)], b: [entry("Mike", mike2)], saved: [mike1, mike2]))
    }

    func testATypedNameMatchingAPickedPlayerIsADuplicate() {
        let mike = SavedPlayer(name: "Mike")
        XCTAssertEqual(duplicate(a: [entry("Mike", mike)], b: [entry("Mike")], saved: [mike]), "Mike")
    }

    func testTheSamePickedPlayerTwiceIsADuplicate() {
        let mike = SavedPlayer(name: "Mike")
        XCTAssertEqual(duplicate(a: [entry("Mike", mike)], b: [entry("Mike", mike)], saved: [mike]), "Mike")
    }

    func testAllDistinctIsNil() {
        let mike = SavedPlayer(name: "Mike")
        XCTAssertNil(duplicate(
            a: [entry("Mike", mike), entry("Zed")], b: [entry("Bob"), entry("Mike S.")], saved: [mike]
        ))
    }

    func testTheReasonSaysWhatToDo() {
        XCTAssertEqual(
            SetupPlayerValidation.reason(forDuplicate: "Mike"),
            "Mike is listed more than once. Add an initial to tell them apart, for example Mike S."
        )
    }
}
