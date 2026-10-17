import XCTest
@testable import ServerTwo

final class TapOrHoldModifierTests: XCTestCase {
    private func isBeyond(_ width: CGFloat, _ height: CGFloat) -> Bool {
        TapOrHoldModifier.isMovementBeyondTapThreshold(translation: CGSize(width: width, height: height))
    }

    func testNoMovementIsNotBeyondThreshold() {
        XCTAssertFalse(isBeyond(0, 0))
    }

    func testJustUnderTwentyPointsIsNotBeyondThreshold() {
        XCTAssertFalse(isBeyond(19.9, 0))
    }

    func testExactlyTwentyPointsIsNotBeyondThreshold() {
        XCTAssertFalse(isBeyond(20, 0))
        XCTAssertFalse(isBeyond(0, -20))
    }

    func testJustOverTwentyPointsIsBeyondThreshold() {
        XCTAssertTrue(isBeyond(20.1, 0))
        XCTAssertTrue(isBeyond(0, -20.1))
    }

    func testDiagonalMovementUsesDistanceNotPerAxisTravel() {
        // 15 on each axis is under 20 per axis but ~21.2 overall.
        XCTAssertTrue(isBeyond(15, 15))
        XCTAssertTrue(isBeyond(-15, 15))
    }
}
