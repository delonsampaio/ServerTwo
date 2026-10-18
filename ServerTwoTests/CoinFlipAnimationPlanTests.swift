import XCTest
@testable import ServerTwo

/// The coin flip's animation is described by a small pure value so the
/// Reduce Motion behaviour can be unit-tested; the view only reads it.
@MainActor
final class CoinFlipAnimationPlanTests: XCTestCase {
    func testNormalPlanMatchesTheCurrentAnimation() {
        XCTAssertEqual(
            CoinFlipAnimationPlan.plan(reduceMotion: false),
            CoinFlipAnimationPlan(spins: true, letterToggles: 6, settleDelay: 0.7)
        )
    }

    func testReduceMotionPlanHasNoSpinNoToggleAndNoDelay() {
        XCTAssertEqual(
            CoinFlipAnimationPlan.plan(reduceMotion: true),
            CoinFlipAnimationPlan(spins: false, letterToggles: 0, settleDelay: 0)
        )
    }
}
