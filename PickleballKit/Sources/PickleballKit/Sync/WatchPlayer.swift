import Foundation

/// A saved player as the iPhone tells the Watch about them (names only, never
/// photos). The Watch lists these in its player picker and sends the chosen
/// `id` back, so the phone can link the exact player (two saved "Mike"s stay
/// apart).
public struct WatchPlayer: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var isMe: Bool

    public init(id: UUID, name: String, isMe: Bool = false) {
        self.id = id
        self.name = name
        self.isMe = isMe
    }
}

/// One player of a Watch match as it travels to the iPhone: the saved player
/// the Watch picked (`nil` for a name typed on the Watch) and the name.
public struct SyncedPlayerRef: Codable, Sendable, Equatable {
    public var savedPlayerID: UUID?
    public var name: String

    public init(savedPlayerID: UUID? = nil, name: String) {
        self.savedPlayerID = savedPlayerID
        self.name = name
    }
}

/// The text rules for a player name on the wire, shared by the phone's list,
/// the Watch's typed names and the phone's import validation.
public enum PlayerNameRules {
    public static let maxLength = 64

    /// Control characters (including newlines) removed and the ends trimmed;
    /// the empty string when nothing is left. Not capped.
    public static func stripped(_ name: String) -> String {
        String(String.UnicodeScalarView(
            name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        )).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `stripped`, cut to `maxLength` characters (and re-trimmed so the cut
    /// leaves no trailing space); `nil` when blank.
    public static func truncated(_ name: String) -> String? {
        let cut = String(stripped(name).prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }

    /// The one line shown when the same player is entered twice: Match Setup,
    /// Edit Players and the Watch's player slots all use it.
    public static func duplicateReason(forName name: String) -> String {
        "\(name) is listed more than once. Add an initial to tell them apart, for example Mike S."
    }

    /// `stripped`, or `nil` when blank or longer than `maxLength` (the import
    /// drops such an entry instead of guessing).
    public static func validated(_ name: String) -> String? {
        let cleaned = stripped(name)
        return cleaned.isEmpty || cleaned.count > maxLength ? nil : cleaned
    }
}

/// Bounds on the phone's player list for the Watch.
public enum WatchPlayerList {
    public static let maxPlayers = 50

    /// What both ends do to a list before using it: blank names dropped, names
    /// cut to `PlayerNameRules.maxLength`, order kept, at most `maxPlayers`.
    public static func normalized(_ players: [WatchPlayer]) -> [WatchPlayer] {
        var result: [WatchPlayer] = []
        for player in players {
            guard let name = PlayerNameRules.truncated(player.name) else { continue }
            result.append(WatchPlayer(id: player.id, name: name, isMe: player.isMe))
            if result.count == maxPlayers { break }
        }
        return result
    }
}
