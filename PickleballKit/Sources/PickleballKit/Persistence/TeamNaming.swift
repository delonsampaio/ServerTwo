import Foundation

/// The one place a side's `TeamSide.displayName` is built from its players'
/// names. Match setup, Quick Log and "Edit Players" all go through it, so a
/// match edited later reads exactly like one saved with the same players
/// (two separately maintained copies of the " & " / placeholder rules would
/// drift apart).
public enum TeamNaming {
    /// What a side is called when nobody was entered for it.
    public static func placeholderName(for team: Team) -> String {
        team == .teamA ? "Team A" : "Team B"
    }

    /// Trimmed, non-blank names joined with `" & "` — the exact literal
    /// `RematchRequest` and `MatchRepository.mySide` split on. Empty when no
    /// name is left, so a blank Player 1 never produces a leading " & ".
    public static func joinedName(_ names: [String]) -> String {
        names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " & ")
    }

    /// `joinedName`, or the placeholder ("Team A"/"Team B") when it is empty.
    public static func displayName(forPlayerNames names: [String], team: Team) -> String {
        resolvedName(joinedName(names), team: team)
    }

    /// Falls back to the placeholder for a blank name; a non-blank name is
    /// returned as given.
    public static func resolvedName(_ name: String, team: Team) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholderName(for: team) : name
    }
}

/// One player slot as the Edit Players sheet holds it: the text in the field
/// plus the saved player the user picked from the suggestions, if any. Plain
/// values (no `SavedPlayer`) so the sheet never carries a model object across
/// a `ModelContext` boundary.
public struct PlayerSlotEntry: Equatable, Sendable {
    public var name: String
    public var savedPlayerID: UUID?

    public init(name: String, savedPlayerID: UUID? = nil) {
        self.name = name
        self.savedPlayerID = savedPlayerID
    }
}

extension PlayerSlotEntry {
    public var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The saved player this entry refers to, or `nil` if it would be new.
    public func matchingPlayer(among players: [SavedPlayer]) -> SavedPlayer? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A picked id only counts while the field still shows that player's
        // name (same rule as MatchSetupView.resolvedPlayer): this is what
        // tells two saved players who share a name apart.
        if let id = savedPlayerID,
           let picked = players.first(where: { $0.id == id }),
           picked.name.caseInsensitiveCompare(trimmed) == .orderedSame {
            return picked
        }
        return players.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// The name (as typed, trimmed) of the first non-blank entry that refers
    /// to the same player as an earlier one: the same saved identity, or for
    /// a not-yet-saved name the same case-insensitive text. Shared by the
    /// repository (which throws on it) and the Edit Players sheet (which
    /// shows it as a reason), so both agree on what a duplicate is.
    public static func firstDuplicateName(in entries: [PlayerSlotEntry], among players: [SavedPlayer]) -> String? {
        var seen = Set<String>()
        for entry in entries where !entry.isBlank {
            let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = entry.matchingPlayer(among: players).map { "id:\($0.id.uuidString)" } ?? "name:\(trimmed.lowercased())"
            if !seen.insert(key).inserted { return trimmed }
        }
        return nil
    }
}

extension TeamSide {
    /// `players` in the order the side's `displayName` lists them. The
    /// relationship itself is an unordered to-many (its order can change
    /// after a CloudKit sync or relaunch), so Player 1/Player 2 slots must
    /// not be read from the array directly. Names are matched
    /// case-insensitively; a player whose name no longer appears in the
    /// display name (e.g. a saved player renamed since) keeps its array
    /// order after the matched ones.
    public var orderedPlayers: [SavedPlayer] {
        let players = self.players ?? []
        let names = displayName.components(separatedBy: " & ")
        var remaining = players
        var ordered: [SavedPlayer] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = remaining.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                ordered.append(remaining.remove(at: index))
            }
        }
        return ordered + remaining
    }
}
