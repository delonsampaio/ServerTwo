import PickleballKit

extension MatchFormat {
    /// The mid-game end change (Rule 21.B) applies only to a single game or the
    /// tie-breaker (deciding) game of a multi-game match: the last game the
    /// format can reach (game 1 of a best of 1, game 3 of a best of 3, game 5
    /// of a best of 5). Between games teams always change ends (Rule 21.F.2).
    func isLastGame(index: Int) -> Bool {
        index == rawValue - 1
    }
}
