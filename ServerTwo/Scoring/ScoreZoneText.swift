import PickleballKit

/// The text on a score card that depends on the rules in play, kept pure so
/// every combination can be unit-tested. In side-out scoring a tap on the
/// receiving team's card does not score: it means "second server" or "side
/// out", and the cards used to say "Tap to Score" regardless, so a user whose
/// Server 1 lost the rally tapped the other card, saw nothing change, and
/// tapped again (an accidental side-out).
enum ScoreZoneCaption {
    static func text(
        isServing: Bool,
        scoringIsSideOut: Bool,
        isDoubles: Bool,
        serverNumber: ServerNumber,
        isMatchOver: Bool
    ) -> String {
        // The cards are disabled once the match is decided; saying "Tap to
        // Score" there made them look live.
        if isMatchOver { return "Match Complete" }
        // Rally scoring: the team that wins the rally scores, whoever served.
        guard scoringIsSideOut, !isServing else { return "Tap to Score" }
        // Doubles Server 1 losing a rally hands the serve to Server 2 (same
        // team); anything else (singles, or Server 2) is a full side out.
        return isDoubles && serverNumber == .one ? "Tap for 2nd Server" : "Tap for Side Out"
    }
}

/// The serving badge's text, or nil when the badge is hidden. Only doubles
/// side-out scoring has a server number worth showing; singles and rally
/// scoring keep plain "SERVING".
enum ServingBadge {
    static func text(
        isServing: Bool,
        scoringIsSideOut: Bool,
        isDoubles: Bool,
        serverNumber: ServerNumber,
        isMatchOver: Bool
    ) -> String? {
        guard isServing, !isMatchOver else { return nil }
        guard scoringIsSideOut, isDoubles else { return "SERVING" }
        return "SERVER \(serverNumber.rawValue)"
    }

    /// The server number the VoiceOver label should append, nil outside
    /// doubles side-out scoring (same rule as the badge).
    static func spokenServerNumber(
        scoringIsSideOut: Bool,
        isDoubles: Bool,
        serverNumber: ServerNumber
    ) -> Int? {
        scoringIsSideOut && isDoubles ? serverNumber.rawValue : nil
    }
}

/// Decides when the "serve changed" haptic fires. The existing score haptic
/// only fires when a score rises, so a second-server or side-out move (no
/// score change) was silent; this covers exactly those moves. Disjoint from
/// the score haptic by construction: a scoring move changes a score, never
/// the serve, so the two cannot double-fire on one tap.
enum ServeChangeHaptic {
    static func shouldFire(old: AnnouncementSnapshot, new: AnnouncementSnapshot) -> Bool {
        // `moveCount` (history length) rises only on a forward move, so an undo
        // (it falls) stays silent; the game index guard keeps a game boundary,
        // where the count resets, from reading as a forward move. Unchanged
        // scores exclude scoring moves and a Correct Score save.
        guard new.gameIndex == old.gameIndex,
              new.moveCount > old.moveCount,
              new.teamAScore == old.teamAScore,
              new.teamBScore == old.teamBScore else { return false }
        return new.servingTeam != old.servingTeam || new.serverNumber != old.serverNumber
    }
}
