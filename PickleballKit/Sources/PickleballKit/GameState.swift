public struct GameState: Codable, Sendable, Equatable {
    public var teamAScore: Int
    public var teamBScore: Int
    public var servingTeam: Team
    public var serverNumber: ServerNumber
    public var teamATimeoutsRemaining: Int
    public var teamBTimeoutsRemaining: Int
    public var hasSideSwitched: Bool
    public var lastPointWonWhileServing: Bool

    public init(
        teamAScore: Int,
        teamBScore: Int,
        servingTeam: Team,
        serverNumber: ServerNumber,
        teamATimeoutsRemaining: Int,
        teamBTimeoutsRemaining: Int,
        hasSideSwitched: Bool,
        lastPointWonWhileServing: Bool
    ) {
        self.teamAScore = teamAScore
        self.teamBScore = teamBScore
        self.servingTeam = servingTeam
        self.serverNumber = serverNumber
        self.teamATimeoutsRemaining = teamATimeoutsRemaining
        self.teamBTimeoutsRemaining = teamBTimeoutsRemaining
        self.hasSideSwitched = hasSideSwitched
        self.lastPointWonWhileServing = lastPointWonWhileServing
    }

    public func score(for team: Team) -> Int {
        team == .teamA ? teamAScore : teamBScore
    }

    public func timeoutsRemaining(for team: Team) -> Int {
        team == .teamA ? teamATimeoutsRemaining : teamBTimeoutsRemaining
    }
}
