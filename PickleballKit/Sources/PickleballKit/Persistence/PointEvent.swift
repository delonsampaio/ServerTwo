import SwiftData
import Foundation

@Model
public final class PointEvent {
    public var id: UUID = UUID()
    public var sequenceNumber: Int = 0
    public var scoringTeamRawValue: String = Team.teamA.rawValue
    public var teamAScoreAfter: Int = 0
    public var teamBScoreAfter: Int = 0
    public var game: GameRecord?

    public init(
        id: UUID = UUID(),
        sequenceNumber: Int,
        scoringTeam: Team,
        teamAScoreAfter: Int,
        teamBScoreAfter: Int
    ) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.scoringTeamRawValue = scoringTeam.rawValue
        self.teamAScoreAfter = teamAScoreAfter
        self.teamBScoreAfter = teamBScoreAfter
    }

    public var scoringTeam: Team {
        Team(rawValue: scoringTeamRawValue) ?? .teamA
    }
}
