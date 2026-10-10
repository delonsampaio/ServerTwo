import SwiftData
import Foundation

@Model
public final class TeamSide {
    public var id: UUID = UUID()
    public var teamRawValue: String = Team.teamA.rawValue
    public var displayName: String = ""

    /// Populated only for matches saved after the Saved Players feature
    /// shipped — `nil` on every match recorded before. `.nullify` (not
    /// `.cascade`): deleting a `SavedPlayer` must remove it from this
    /// array without touching the match it played in.
    @Relationship(deleteRule: .nullify, inverse: \SavedPlayer.teamSides)
    public var players: [SavedPlayer]? = nil

    public var match: MatchRecord?

    public init(id: UUID = UUID(), team: Team, displayName: String) {
        self.id = id
        self.teamRawValue = team.rawValue
        self.displayName = displayName
    }

    public var team: Team {
        Team(rawValue: teamRawValue) ?? .teamA
    }
}
