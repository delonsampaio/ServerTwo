import Foundation
import PickleballKit

/// The "same person entered twice" decision for match setup, with no UI so it
/// can be unit tested without a simulator.
enum SetupPlayerValidation {
    /// The name (as typed, trimmed) of the first player who appears in more
    /// than one slot that is in play, or `nil` when everyone is distinct.
    /// Each team passes its slots as [Player 1, Player 2]; singles looks at
    /// Player 1 only, so a leftover Player 2 from doubles never counts. The
    /// identity rule itself (picked id, else matching saved name, else the
    /// lowercased new name) lives in `PlayerSlotEntry.firstDuplicateName`,
    /// shared with the Edit Players sheet.
    static func duplicateName(
        teamA: [PlayerSlotEntry],
        teamB: [PlayerSlotEntry],
        isDoubles: Bool,
        among savedPlayers: [SavedPlayer]
    ) -> String? {
        let inPlay = isDoubles
            ? Array(teamA.prefix(2)) + Array(teamB.prefix(2))
            : Array(teamA.prefix(1)) + Array(teamB.prefix(1))
        return PlayerSlotEntry.firstDuplicateName(in: inPlay, among: savedPlayers)
    }

    /// The one line both setup and the Edit Players sheet show for a repeated
    /// player.
    static func reason(forDuplicate name: String) -> String {
        "\(name) is listed more than once. Add an initial to tell them apart, for example Mike S."
    }
}
