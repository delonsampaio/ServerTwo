import XCTest
@testable import PickleballKit

final class WatchPlayerSelectionTests: XCTestCase {
    private let mike = SyncedPlayerRef(savedPlayerID: UUID(), name: "Mike")
    private let sarah = SyncedPlayerRef(savedPlayerID: UUID(), name: "Sarah")
    private let ann = SyncedPlayerRef(name: "Ann")
    private let bo = SyncedPlayerRef(name: "Bo")

    private func slot(_ team: Team, _ index: Int) -> WatchPlayerSelection.Slot { .init(team: team, index: index) }

    // MARK: Slots follow the play mode

    func testSlotsByPlayMode() {
        XCTAssertEqual(WatchPlayerSelection.slots(for: .singles), [slot(.teamA, 0), slot(.teamB, 0)])
        XCTAssertEqual(
            WatchPlayerSelection.slots(for: .doubles),
            [slot(.teamA, 0), slot(.teamA, 1), slot(.teamB, 0), slot(.teamB, 1)]
        )
        XCTAssertEqual(slot(.teamA, 1).title(for: .doubles), "Team A, player 2")
        XCTAssertEqual(slot(.teamB, 0).title(for: .singles), "Team B")
    }

    func testAssignAndClear() {
        var selection = WatchPlayerSelection()
        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.assign(mike, to: slot(.teamA, 0), mode: .doubles), .assigned)
        XCTAssertEqual(selection.entry(at: slot(.teamA, 0)), mike)
        XCTAssertFalse(selection.isEmpty)
        selection.clear(slot(.teamA, 0))
        XCTAssertTrue(selection.isEmpty)
        selection.assign(ann, to: slot(.teamB, 1), mode: .doubles)
        selection.clearAll()
        XCTAssertTrue(selection.isEmpty)
    }

    func testASlotOutsideThePlayModeIsRefused() {
        var selection = WatchPlayerSelection()
        XCTAssertNotEqual(selection.assign(mike, to: slot(.teamA, 1), mode: .singles), .assigned)
        XCTAssertTrue(selection.isEmpty)
    }

    func testReplacingASlotWithTheSamePlayerIsFine() {
        var selection = WatchPlayerSelection()
        selection.assign(mike, to: slot(.teamA, 0), mode: .doubles)
        XCTAssertEqual(selection.assign(mike, to: slot(.teamA, 0), mode: .doubles), .assigned)
    }

    // MARK: Slicing for a match

    func testMatchPlayersAreSlicedToThePlayMode() {
        var selection = WatchPlayerSelection()
        selection.assign(mike, to: slot(.teamA, 0), mode: .doubles)
        selection.assign(sarah, to: slot(.teamA, 1), mode: .doubles)
        selection.assign(ann, to: slot(.teamB, 0), mode: .doubles)
        selection.assign(bo, to: slot(.teamB, 1), mode: .doubles)

        XCTAssertEqual(selection.matchPlayers(for: .doubles), WatchMatchPlayers(teamA: [mike, sarah], teamB: [ann, bo]))
        // Switching to singles cannot leave "Mike & Sarah" in the match...
        XCTAssertEqual(selection.matchPlayers(for: .singles), WatchMatchPlayers(teamA: [mike], teamB: [ann]))
        // ...and switching back brings the second players back.
        XCTAssertEqual(selection.matchPlayers(for: .doubles).teamA, [mike, sarah])
    }

    func testAnEmptyFirstSlotLetsTheSecondPlayerComeUp() {
        var selection = WatchPlayerSelection()
        selection.assign(sarah, to: slot(.teamA, 1), mode: .doubles)
        XCTAssertEqual(selection.matchPlayers(for: .doubles).teamA, [sarah])
        XCTAssertEqual(selection.matchPlayers(for: .singles).teamA, [], "slot 2 is not in play in singles")
    }

    func testSummaryText() {
        var selection = WatchPlayerSelection()
        XCTAssertNil(selection.summary(for: .doubles))
        selection.assign(mike, to: slot(.teamA, 0), mode: .doubles)
        selection.assign(sarah, to: slot(.teamA, 1), mode: .doubles)
        selection.assign(ann, to: slot(.teamB, 0), mode: .doubles)
        XCTAssertEqual(selection.summary(for: .doubles), "Mike & Sarah vs Ann")
        XCTAssertEqual(selection.summary(for: .singles), "Mike vs Ann")
    }

    // MARK: Duplicates, with the phone's wording

    func testTheSamePlayerInTwoSlotsIsRefusedWithThePhonesWording() {
        var selection = WatchPlayerSelection()
        selection.assign(mike, to: slot(.teamA, 0), mode: .doubles)
        let result = selection.assign(mike, to: slot(.teamB, 0), mode: .doubles)
        XCTAssertEqual(result, .refused(reason: "Mike is listed more than once. Add an initial to tell them apart, for example Mike S."))
        XCTAssertNil(selection.entry(at: slot(.teamB, 0)))
        // On the same side too.
        XCTAssertNotEqual(selection.assign(mike, to: slot(.teamA, 1), mode: .doubles), .assigned)
    }

    func testTypedNamesDuplicateCaseInsensitivelyButTwoSavedPlayersWithOneNameDoNot() {
        var selection = WatchPlayerSelection()
        selection.assign(SyncedPlayerRef(name: "Ann"), to: slot(.teamA, 0), mode: .doubles)
        XCTAssertNotEqual(selection.assign(SyncedPlayerRef(name: " aNN "), to: slot(.teamB, 0), mode: .doubles), .assigned)

        let twinA = SyncedPlayerRef(savedPlayerID: UUID(), name: "Twin")
        let twinB = SyncedPlayerRef(savedPlayerID: UUID(), name: "Twin")
        selection.assign(twinA, to: slot(.teamA, 1), mode: .doubles)
        XCTAssertEqual(selection.assign(twinB, to: slot(.teamB, 0), mode: .doubles), .assigned, "picked by id, they stay apart")
    }

    func testAHiddenDoublesSlotDoesNotCountInSingles() {
        var selection = WatchPlayerSelection()
        selection.assign(mike, to: slot(.teamA, 1), mode: .doubles)
        // In singles Team A's second slot is not in play, so Mike may play Team B.
        XCTAssertEqual(selection.assign(mike, to: slot(.teamB, 0), mode: .singles), .assigned)
        XCTAssertNil(selection.duplicateName(for: .singles))
        XCTAssertEqual(selection.duplicateName(for: .doubles), "Mike")
    }

    func testPickerRowsUsedElsewhereAreReported() {
        var selection = WatchPlayerSelection()
        selection.assign(mike, to: slot(.teamA, 0), mode: .doubles)
        XCTAssertTrue(selection.isUsed(mike, excluding: slot(.teamB, 0), mode: .doubles))
        XCTAssertFalse(selection.isUsed(mike, excluding: slot(.teamA, 0), mode: .doubles), "its own slot")
        XCTAssertFalse(selection.isUsed(sarah, excluding: slot(.teamB, 0), mode: .doubles))
    }

    // MARK: Names and persistence

    func testNamesAreCleanedAndBlankIsRefused() {
        var selection = WatchPlayerSelection()
        selection.assign(SyncedPlayerRef(name: "  Ann\n "), to: slot(.teamA, 0), mode: .singles)
        XCTAssertEqual(selection.entry(at: slot(.teamA, 0))?.name, "Ann")
        XCTAssertNotEqual(selection.assign(SyncedPlayerRef(name: "   "), to: slot(.teamB, 0), mode: .singles), .assigned)
        selection.assign(SyncedPlayerRef(name: String(repeating: "z", count: 100)), to: slot(.teamB, 0), mode: .singles)
        XCTAssertEqual(selection.entry(at: slot(.teamB, 0))?.name.count, 64)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "WatchPlayerSelectionTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testTheLastSelectionComesBackInANewInstanceAndClearingStaysCleared() {
        let defaults = makeDefaults()
        var last = LastUsedPlayers(userDefaults: defaults)
        XCTAssertTrue(last.selection.isEmpty, "defaults to nobody chosen")
        last.selection.assign(mike, to: slot(.teamA, 0), mode: .doubles)
        last.selection.assign(ann, to: slot(.teamB, 1), mode: .doubles)
        last.save()

        var reloaded = LastUsedPlayers(userDefaults: defaults)
        XCTAssertEqual(reloaded.selection, last.selection)
        XCTAssertEqual(reloaded.selection.entry(at: slot(.teamB, 1)), ann)

        reloaded.selection.clearAll()
        reloaded.save()
        XCTAssertTrue(LastUsedPlayers(userDefaults: defaults).selection.isEmpty)
    }

    func testStoredDataIsCappedAndCleanedOnLoad() throws {
        let defaults = makeDefaults()
        let json = """
        {"teamA": [{"name": "A1"}, {"name": "  "}, {"name": "A3"}, {"name": "A4"}],
         "teamB": [{"name": "\(String(repeating: "q", count: 90))"}]}
        """
        defaults.set(Data(json.utf8), forKey: LastUsedPlayers.key)
        let selection = LastUsedPlayers(userDefaults: defaults).selection
        XCTAssertEqual(selection.teamA.count, 2)
        XCTAssertEqual(selection.entry(at: slot(.teamA, 0))?.name, "A1")
        XCTAssertNil(selection.entry(at: slot(.teamA, 1)), "blank dropped, third and fourth cut off")
        XCTAssertEqual(selection.entry(at: slot(.teamB, 0))?.name.count, 64)
        XCTAssertEqual(selection.teamB.count, 2)

        defaults.set(Data([1, 2]), forKey: LastUsedPlayers.key)
        XCTAssertTrue(LastUsedPlayers(userDefaults: defaults).selection.isEmpty, "unreadable falls back to empty")
    }
}
