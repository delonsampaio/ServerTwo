import SwiftData
import Foundation

@Model
public final class GameRecord {
    public var id: UUID = UUID()
    public var gameNumber: Int = 1
    public var teamAFinalScore: Int = 0
    public var teamBFinalScore: Int = 0
    public var winningTeamRawValue: String = Team.teamA.rawValue
    public var match: MatchRecord?

    /// SwiftData to-many relationship arrays have no guaranteed order —
    /// do not rely on this array's order directly (in particular, `.last`
    /// is not "the most recent point"). Use `orderedPoints` instead.
    @Relationship(deleteRule: .cascade, inverse: \PointEvent.game)
    public var points: [PointEvent]? = []

    /// `points` sorted by `sequenceNumber` — use this, not `points`
    /// directly, whenever point order matters (e.g. a point-by-point log).
    public var orderedPoints: [PointEvent] {
        (points ?? []).sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    public init(
        id: UUID = UUID(),
        gameNumber: Int,
        teamAFinalScore: Int,
        teamBFinalScore: Int,
        winningTeam: Team
    ) {
        self.id = id
        self.gameNumber = gameNumber
        self.teamAFinalScore = teamAFinalScore
        self.teamBFinalScore = teamBFinalScore
        self.winningTeamRawValue = winningTeam.rawValue
    }

    public var winningTeam: Team {
        Team(rawValue: winningTeamRawValue) ?? .teamA
    }
}
