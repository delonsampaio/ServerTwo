import Foundation

/// Which partner stands on which side of a doubles team's own court. Pure and
/// app-side (not in PickleballKit): it needs the player names, which the engine
/// has no concept of.
///
/// Rule (side-out doubles only): partners swap sides only when THEIR team scores
/// while serving, so a team's own score parity decides who stands where. Player 1
/// (the first name typed in Setup) starts each game on the right unless the
/// team's override flag says they started the other way round.
struct PartnerPositions: Equatable {
    enum Side: Equatable {
        case right, left

        var badge: String { self == .right ? "R" : "L" }
        var spoken: String { self == .right ? "right" : "left" }
        var opposite: Side { self == .right ? .left : .right }
    }

    let player1Name: String
    let player1Side: Side
    let player2Name: String
    let player2Side: Side

    /// `nil` when `teamName` does not split into exactly two non-empty names
    /// (the "Team A" fallback, one name typed): the card then shows its normal
    /// single name line and no positions. The separator is the exact literal
    /// " & " (how Setup combines the two typed names), so a name that merely
    /// contains "&" stays intact.
    static func make(teamName: String, score: Int, swapped: Bool) -> PartnerPositions? {
        let parts = teamName.components(separatedBy: " & ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        // A team's score only rises while it serves, one swap per point, so its
        // swap count always equals its score: parity alone is enough.
        let player1OnRight = (score % 2 == 0) != swapped
        let player1Side: Side = player1OnRight ? .right : .left
        return PartnerPositions(
            player1Name: parts[0], player1Side: player1Side,
            player2Name: parts[1], player2Side: player1Side.opposite
        )
    }

    /// Spoken by VoiceOver, right side first so the order is the same whoever
    /// stands where: "Delon on the right, Katie on the left".
    var spokenSummary: String {
        let (right, left) = player1Side == .right
            ? (player1Name, player2Name) : (player2Name, player1Name)
        return "\(right) on the right, \(left) on the left"
    }

    /// Compact preview for the correction sheet: "Delon R · Katie L".
    var previewText: String {
        "\(player1Name) \(player1Side.badge) · \(player2Name) \(player2Side.badge)"
    }
}
