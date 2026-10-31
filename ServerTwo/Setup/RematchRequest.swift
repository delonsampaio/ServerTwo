import Foundation
import PickleballKit

/// A one-shot payload for "start a new match with the same players and
/// rules as this one." Deliberately plain/value-typed (no `SavedPlayer` or
/// `MatchRecord` references) — this app already paid for the lesson, in
/// `ActiveMatchController`, that carrying a SwiftData model object across a
/// tab/view boundary risks a cross-`ModelContext` bug if the underlying row
/// is deleted or renamed in between. `MatchSetupView` re-resolves each
/// player by id in its own context when it actually starts the match, the
/// same way a tapped suggestion chip already does.
struct RematchRequest: Equatable, Identifiable {
    struct PlayerSlot: Equatable {
        let name: String
        let savedPlayerID: UUID?
    }

    let id = UUID()
    let configuration: GameConfiguration
    let matchFormat: MatchFormat
    let teamAPlayer1: PlayerSlot
    let teamAPlayer2: PlayerSlot?
    let teamBPlayer1: PlayerSlot
    let teamBPlayer2: PlayerSlot?

    static func == (lhs: RematchRequest, rhs: RematchRequest) -> Bool {
        lhs.id == rhs.id
    }

    /// `nil` if the match's stored rules can't be decoded — rather than
    /// prefilling a half-correct form, the caller should just not offer a
    /// Rematch button for that match.
    init?(match: MatchRecord) {
        guard let configuration = try? JSONDecoder().decode(GameConfiguration.self, from: match.configurationData) else {
            return nil
        }
        guard let teamASide = (match.teamSides ?? []).first(where: { $0.team == .teamA }),
              let teamBSide = (match.teamSides ?? []).first(where: { $0.team == .teamB }) else {
            return nil
        }
        self.configuration = configuration
        self.matchFormat = match.matchFormat
        (teamAPlayer1, teamAPlayer2) = Self.playerSlots(for: teamASide)
        (teamBPlayer1, teamBPlayer2) = Self.playerSlots(for: teamBSide)
    }

    private static func playerSlots(for side: TeamSide) -> (PlayerSlot, PlayerSlot?) {
        let players = side.orderedPlayers
        if !players.isEmpty {
            let first = PlayerSlot(name: players[0].name, savedPlayerID: players[0].id)
            let second = players.count > 1 ? PlayerSlot(name: players[1].name, savedPlayerID: players[1].id) : nil
            return (first, second)
        }
        // A side nobody was entered for is named "Team A"/"Team B": a
        // placeholder, not a player (the same guard as
        // `EditMatchPlayersValidation.currentEntries`). Prefilling it would turn
        // it into a real SavedPlayer when the rematch starts.
        guard side.displayName != TeamNaming.placeholderName(for: side.team) else {
            return (PlayerSlot(name: "", savedPlayerID: nil), nil)
        }
        // Legacy match, saved before SavedPlayer existed: `players` is nil
        // and all we have is the free-text display name. Split ONLY on the
        // exact literal " & " — the one and only separator this app itself
        // ever writes (see `MatchSetupView.combinedName`). A fuzzy
        // multi-delimiter heuristic (splitting on "and", "/", etc.) would
        // corrupt a real name like "Andy" or "Anderson" — already rejected
        // once in this project's design for exactly that reason.
        let parts = side.displayName.components(separatedBy: " & ")
        let first = PlayerSlot(name: parts.first ?? side.displayName, savedPlayerID: nil)
        let second = parts.count > 1 ? PlayerSlot(name: parts[1], savedPlayerID: nil) : nil
        return (first, second)
    }
}
