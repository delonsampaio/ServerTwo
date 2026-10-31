/// The screens of the standalone Watch app.
public enum WatchScreen: Equatable, Sendable {
    case home, coinFlip, scoring, gameOver, matchOver
}

/// Which screen to show, as a pure function of the session's state and the one
/// piece of navigation the session does not own: whether the player is on the
/// coin-flip step before a match exists. Kept out of the views because a stale
/// coin-flip flag once sent the watch back to the coin flip after "Done" (the
/// flag was set when Start Match was tapped and never cleared when the match
/// began); `matchBegan()` is that clear, and every transition is unit-tested.
public struct WatchFlow: Equatable, Sendable {
    public private(set) var isChoosingFirstServer = false

    public init() {}

    public mutating func startMatchTapped() { isChoosingFirstServer = true }
    public mutating func coinFlipCancelled() { isChoosingFirstServer = false }
    /// Call when the coin flip is confirmed and the session starts the match.
    public mutating func matchBegan() { isChoosingFirstServer = false }

    public func screen(isActive: Bool, isGameOver: Bool, isMatchOver: Bool) -> WatchScreen {
        // A live (or resumed) match always wins over the coin-flip flag.
        guard isActive else { return isChoosingFirstServer ? .coinFlip : .home }
        if isMatchOver { return .matchOver }
        if isGameOver { return .gameOver }
        return .scoring
    }
}
