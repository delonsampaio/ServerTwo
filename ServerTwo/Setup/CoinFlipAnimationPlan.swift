import Foundation

/// How the coin flip animates. With Reduce Motion on, the coin does not spin,
/// the letter does not toggle and the result settles immediately.
struct CoinFlipAnimationPlan: Equatable {
    let spins: Bool
    let letterToggles: Int
    let settleDelay: TimeInterval

    static func plan(reduceMotion: Bool) -> CoinFlipAnimationPlan {
        reduceMotion
            ? CoinFlipAnimationPlan(spins: false, letterToggles: 0, settleDelay: 0)
            : CoinFlipAnimationPlan(spins: true, letterToggles: 6, settleDelay: 0.7)
    }
}
