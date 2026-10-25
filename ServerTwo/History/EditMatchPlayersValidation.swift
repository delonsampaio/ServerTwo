import Foundation
import PickleballKit

/// The decisions behind the Edit Players sheet that need no UI, so they can be
/// unit tested without a simulator: how many slots a side offers, what the
/// slots start with, and whether the current entries can be saved.
enum EditMatchPlayersValidation {
    /// The players a side has right now, as editable entries. Linked players
    /// win; a legacy side (nothing linked) falls back to its display name split
    /// on the exact " & " this app writes — except the "Team A"/"Team B"
    /// placeholder, which is no one.
    static func currentEntries(linked: [PlayerSlotEntry], displayName: String, team: Team) -> [PlayerSlotEntry] {
        if !linked.isEmpty { return linked }
        guard displayName != TeamNaming.placeholderName(for: team) else { return [] }
        return displayName.components(separatedBy: " & ")
            .map { PlayerSlotEntry(name: $0) }
            .filter { !$0.isBlank }
    }

    /// Two slots in doubles, one in singles, but never fewer than the side
    /// already has (a side with two names must not lose one just by opening
    /// the sheet) and never more than two. `isDoubles` is `nil` when the
    /// stored rules can't be decoded, which is treated as doubles.
    static func slotCount(isDoubles: Bool?, currentPlayerCount: Int) -> Int {
        let fromRules = isDoubles == false ? 1 : 2
        return min(2, max(fromRules, currentPlayerCount, 1))
    }

    /// `entries` cut or padded with blank slots to exactly `count`.
    static func slots(_ entries: [PlayerSlotEntry], count: Int) -> [PlayerSlotEntry] {
        Array((entries + Array(repeating: PlayerSlotEntry(name: ""), count: count)).prefix(count))
    }

    /// One line saying why Save is disabled, or `nil` when it may be saved.
    /// Blank slots are fine (they are filled in later); only the same player
    /// twice — in one team or across both — is a problem.
    static func problem(
        teamA: [PlayerSlotEntry],
        teamB: [PlayerSlotEntry],
        savedPlayers: [SavedPlayer]
    ) -> String? {
        guard let name = PlayerSlotEntry.firstDuplicateName(in: teamA + teamB, among: savedPlayers) else {
            return nil
        }
        return SetupPlayerValidation.reason(forDuplicate: name)
    }
}
