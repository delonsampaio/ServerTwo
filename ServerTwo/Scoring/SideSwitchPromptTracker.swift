/// Remembers, per game index, the last `hasSideSwitched` value the user was
/// told about (missing = false, a fresh game's value). A plain "already
/// prompted for this game" flag isn't enough: undo and score correction
/// restore the whole earlier game state including `hasSideSwitched`, so
/// dropping back under the threshold and crossing it again flips the court's
/// sides again and must prompt again. Per-index (not one value) so undoing
/// from game 2 back into game 1, whose flag is still true, doesn't prompt
/// spuriously.
struct SideSwitchPromptTracker: Equatable {
    private(set) var promptedState: [Int: Bool] = [:]

    /// Starts from the live match instead of assuming a fresh one. A match
    /// restored after a relaunch can already be past the threshold, and
    /// `onChange` doesn't fire for a view's initial value, so without this the
    /// first sync would announce a side switch the user already made.
    mutating func seed(completedGameFlags: [Bool], currentGameFlag: Bool) {
        promptedState = [:]
        for (index, flag) in completedGameFlags.enumerated() {
            promptedState[index] = flag
        }
        promptedState[completedGameFlags.count] = currentGameFlag
    }

    /// Idempotent: returns a direction only when the live flag differs from
    /// what the user was last told for this game, and records it, so calling
    /// it from every place the flag might have changed can't double-prompt.
    mutating func next(gameIndex: Int, hasSwitched: Bool) -> ScoringPrompt.SideSwitchDirection? {
        guard let direction = ScoringPrompt.sideSwitchDirection(
            hasSwitched: hasSwitched, promptedState: promptedState[gameIndex] ?? false
        ) else { return nil }
        promptedState[gameIndex] = hasSwitched
        return direction
    }

    /// A queued prompt for this game was dropped as stale without the user
    /// seeing it, so what they were "last told" is whatever the court
    /// actually is now; otherwise the next sync would announce the opposite
    /// direction of a change that never reached them.
    mutating func resync(gameIndex: Int, to hasSwitched: Bool) {
        promptedState[gameIndex] = hasSwitched
    }
}
