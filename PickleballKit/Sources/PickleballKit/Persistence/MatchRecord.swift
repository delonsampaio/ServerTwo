import SwiftData
import Foundation

@Model
public final class MatchRecord {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    public var completedAt: Date = Date()
    public var matchFormatRawValue: Int = MatchFormat.bestOfOne.rawValue
    public var winningTeamRawValue: String = Team.teamA.rawValue
    public var configurationData: Data = Data()

    @Relationship(deleteRule: .cascade, inverse: \TeamSide.match)
    public var teamSides: [TeamSide]? = []

    @Relationship(deleteRule: .cascade, inverse: \GameRecord.match)
    public var games: [GameRecord]? = []

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        completedAt: Date,
        matchFormat: MatchFormat,
        winningTeam: Team,
        configurationData: Data
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.matchFormatRawValue = matchFormat.rawValue
        self.winningTeamRawValue = winningTeam.rawValue
        self.configurationData = configurationData
    }

    public var matchFormat: MatchFormat {
        MatchFormat(rawValue: matchFormatRawValue) ?? .bestOfOne
    }

    public var winningTeam: Team {
        Team(rawValue: winningTeamRawValue) ?? .teamA
    }
}
