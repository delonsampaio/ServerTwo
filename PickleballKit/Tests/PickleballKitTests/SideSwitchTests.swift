import XCTest
@testable import PickleballKit

/// The side-switch helpers the iPhone's scoring screen and the Watch session
/// share. The iOS app's own tests for `isLastGame` and the tracker still run
/// against these same types; these pin them inside the package too.
final class SideSwitchTests: XCTestCase {
    func testIsLastGameIsTheLastGameTheFormatCanReach() {
        XCTAssertTrue(MatchFormat.bestOfOne.isLastGame(index: 0))
        XCTAssertFalse(MatchFormat.bestOfOne.isLastGame(index: 1))
        XCTAssertFalse(MatchFormat.bestOfThree.isLastGame(index: 0))
        XCTAssertFalse(MatchFormat.bestOfThree.isLastGame(index: 1))
        XCTAssertTrue(MatchFormat.bestOfThree.isLastGame(index: 2))
        XCTAssertFalse(MatchFormat.bestOfFive.isLastGame(index: 3))
        XCTAssertTrue(MatchFormat.bestOfFive.isLastGame(index: 4))
    }

    func testDirectionFromFlagAndPromptedState() {
        XCTAssertEqual(SideSwitchDirection.needed(hasSwitched: true, promptedState: false), .switchSides)
        XCTAssertEqual(SideSwitchDirection.needed(hasSwitched: false, promptedState: true), .switchBack)
        XCTAssertNil(SideSwitchDirection.needed(hasSwitched: true, promptedState: true))
        XCTAssertNil(SideSwitchDirection.needed(hasSwitched: false, promptedState: false))
    }

    func testFreshMatchPromptsOnceWhenTheFlagFirstSets() {
        var tracker = SideSwitchPromptTracker()
        tracker.seed(completedGameFlags: [], currentGameFlag: false)
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: false))
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: true), .switchSides)
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: true))
    }

    func testResumedPastTheThresholdDoesNotPromptOnSync() {
        var tracker = SideSwitchPromptTracker()
        tracker.seed(completedGameFlags: [], currentGameFlag: true)
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: true))
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: false), .switchBack)
    }

    func testPerIndexStateKeepsGamesIndependent() {
        var tracker = SideSwitchPromptTracker()
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: true), .switchSides)
        XCTAssertNil(tracker.next(gameIndex: 1, hasSwitched: false))
        XCTAssertEqual(tracker.next(gameIndex: 1, hasSwitched: true), .switchSides)
    }

    func testResyncAfterDroppingAStalePromptPreventsABogusOppositePrompt() {
        var tracker = SideSwitchPromptTracker()
        XCTAssertEqual(tracker.next(gameIndex: 0, hasSwitched: true), .switchSides)
        tracker.resync(gameIndex: 0, to: false)
        XCTAssertNil(tracker.next(gameIndex: 0, hasSwitched: false))
    }
}
