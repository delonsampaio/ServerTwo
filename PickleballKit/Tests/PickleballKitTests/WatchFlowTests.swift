import XCTest
@testable import PickleballKit

/// The screen the Watch shows, as a pure function of the session's state and
/// the one piece of navigation state the session does not own (the coin-flip
/// step). A stale coin-flip flag once sent the watch back to the coin flip
/// after "Done"; these pin every transition.
final class WatchFlowTests: XCTestCase {
    private func screen(
        _ flow: WatchFlow, active: Bool = false, gameOver: Bool = false, matchOver: Bool = false
    ) -> WatchScreen {
        flow.screen(isActive: active, isGameOver: gameOver, isMatchOver: matchOver)
    }

    func testLaunchWithNoMatchShowsHome() {
        XCTAssertEqual(screen(WatchFlow()), .home)
    }

    func testStartMatchGoesToCoinFlipAndCancelReturnsHome() {
        var flow = WatchFlow()
        flow.startMatchTapped()
        XCTAssertEqual(screen(flow), .coinFlip)
        flow.coinFlipCancelled()
        XCTAssertEqual(screen(flow), .home)
    }

    func testBeginningTheMatchShowsScoring() {
        var flow = WatchFlow()
        flow.startMatchTapped()
        flow.matchBegan()
        XCTAssertEqual(screen(flow, active: true), .scoring)
    }

    func testDoneAfterMatchOverReturnsHomeNotCoinFlip() {
        var flow = WatchFlow()
        flow.startMatchTapped()
        flow.matchBegan()
        XCTAssertEqual(screen(flow, active: true, matchOver: true), .matchOver)
        // "Done": the session goes idle.
        XCTAssertEqual(screen(flow, active: false), .home)
    }

    func testAbandoningReturnsHome() {
        var flow = WatchFlow()
        flow.startMatchTapped()
        flow.matchBegan()
        XCTAssertEqual(screen(flow, active: true), .scoring)
        XCTAssertEqual(screen(flow, active: false), .home)
    }

    func testGameOverThenNextGameThenScoring() {
        var flow = WatchFlow()
        flow.startMatchTapped()
        flow.matchBegan()
        XCTAssertEqual(screen(flow, active: true, gameOver: true), .gameOver)
        XCTAssertEqual(screen(flow, active: true, gameOver: false), .scoring)
    }

    func testRelaunchWithAResumedMatchGoesStraightToTheRightScreen() {
        XCTAssertEqual(screen(WatchFlow(), active: true), .scoring)
        XCTAssertEqual(screen(WatchFlow(), active: true, gameOver: true), .gameOver)
    }

    func testMatchOverTakesPrecedenceOverGameOver() {
        XCTAssertEqual(screen(WatchFlow(), active: true, gameOver: true, matchOver: true), .matchOver)
    }

    func testAnActiveMatchAlwaysWinsOverAStaleCoinFlipFlag() {
        var flow = WatchFlow()
        flow.startMatchTapped()
        XCTAssertEqual(screen(flow, active: true), .scoring)
    }
}
