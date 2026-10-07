import SwiftData

@Model
public final class TeamSide {
    public var teamRawValue: String = Team.teamA.rawValue
    public var displayName: String = ""
    public var match: MatchRecord?

    public init(team: Team, displayName: String) {
        self.teamRawValue = team.rawValue
        self.displayName = displayName
    }

    public var team: Team {
        Team(rawValue: teamRawValue) ?? .teamA
    }
}
