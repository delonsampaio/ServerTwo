import SwiftData
import Foundation

@Model
public final class TeamSide {
    public var id: UUID = UUID()
    public var teamRawValue: String = Team.teamA.rawValue
    public var displayName: String = ""
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
