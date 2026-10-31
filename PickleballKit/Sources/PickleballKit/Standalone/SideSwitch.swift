/// Which way the courts' ends change. `switchBack` is the undo/correction
/// case: the engine restores the whole earlier game state including
/// `hasSideSwitched`, so dropping back under the threshold puts the teams back
/// on their starting ends.
public enum SideSwitchDirection: Equatable, Sendable {
    case switchSides
    case switchBack

    /// What (if anything) the user needs telling, given the live
    /// `hasSideSwitched` flag and the value they were last prompted about for
    /// this game. Equal means they already know the current state of the court.
    public static func needed(hasSwitched: Bool, promptedState: Bool) -> SideSwitchDirection? {
        switch (hasSwitched, promptedState) {
        case (true, false): .switchSides
        case (false, true): .switchBack
        default: nil
        }
    }
}

extension MatchFormat {
    /// The mid-game end change (Rule 21.B) applies only to a single game or the
    /// tie-breaker (deciding) game of a multi-game match: the last game the
    /// format can reach (game 1 of a best of 1, game 3 of a best of 3, game 5
    /// of a best of 5). Between games teams always change ends (Rule 21.F.2).
    public func isLastGame(index: Int) -> Bool {
        index == rawValue - 1
    }
}

/// Remembers, per game index, the last `hasSideSwitched` value the user was
/// told about (missing = false, a fresh game's value). A plain "already
/// prompted for this game" flag isn't enough: undo and score correction
/// restore the whole earlier game state including `hasSideSwitched`, so
/// dropping back under the threshold and crossing it again flips the court's
/// sides again and must prompt again. Per-index (not one value) so undoing
/// from game 2 back into game 1, whose flag is still true, doesn't prompt
/// spuriously.
///
/// Shared by the iPhone scoring screen and the Watch session so both announce
/// the change of ends under exactly the same rules.
public struct SideSwitchPromptTracker: Equatable, Sendable {
    public private(set) var promptedState: [Int: Bool] = [:]

    public init() {}

    /// Starts from the live match instead of assuming a fresh one. A match
    /// restored after a relaunch can already be past the threshold, and
    /// `onChange` doesn't fire for a view's initial value, so without this the
    /// first sync would announce a side switch the user already made.
    public mutating func seed(completedGameFlags: [Bool], currentGameFlag: Bool) {
        promptedState = [:]
        for (index, flag) in completedGameFlags.enumerated() {
            promptedState[index] = flag
        }
        promptedState[completedGameFlags.count] = currentGameFlag
    }

    /// Idempotent: returns a direction only when the live flag differs from
    /// what the user was last told for this game, and records it, so calling
    /// it from every place the flag might have changed can't double-prompt.
    public mutating func next(gameIndex: Int, hasSwitched: Bool) -> SideSwitchDirection? {
        guard let direction = SideSwitchDirection.needed(
            hasSwitched: hasSwitched, promptedState: promptedState[gameIndex] ?? false
        ) else { return nil }
        promptedState[gameIndex] = hasSwitched
        return direction
    }

    /// A queued prompt for this game was dropped as stale without the user
    /// seeing it, so what they were "last told" is whatever the court
    /// actually is now; otherwise the next sync would announce the opposite
    /// direction of a change that never reached them.
    public mutating func resync(gameIndex: Int, to hasSwitched: Bool) {
        promptedState[gameIndex] = hasSwitched
    }
}
