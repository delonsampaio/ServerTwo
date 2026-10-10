import SwiftData
import Foundation

/// A persistent player identity, independent of any single match's
/// free-typed display names. Exists purely as a setup-time convenience and
/// a stats-attribution anchor — it does not replace `TeamSide.displayName`,
/// which remains the source of truth for what a match's scoreboard shows.
@Model
public final class SavedPlayer {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Exactly one `SavedPlayer` should have this `true` at a time —
    /// enforced by `MatchRepository.setMePlayer`, not by the model itself.
    public var isMe: Bool = false

    /// Inverse side of `TeamSide.players` — every match side this player
    /// has been part of. Not used by any current query (stats scan forward
    /// from `MatchRecord` → `TeamSide` → `players`), but declared so the
    /// relationship is properly bidirectional, matching every other
    /// to-many relationship already in this schema.
    public var teamSides: [TeamSide]? = []

    public init(id: UUID = UUID(), name: String, isMe: Bool = false) {
        self.id = id
        self.name = name
        self.isMe = isMe
    }
}
