public struct GameState: Codable, Sendable, Equatable {
    public var teamAScore: Int
    public var teamBScore: Int
    public var servingTeam: Team
    public var serverNumber: ServerNumber
    public var teamATimeoutsRemaining: Int
    public var teamBTimeoutsRemaining: Int
    /// A one-shot flag: once set `true`, it stays `true` for the rest of the
    /// game and never resets. UI code binding to it directly will keep
    /// showing an alert/notification state rather than firing once; callers
    /// needing a one-time notification must track their own "already
    /// acknowledged" state alongside this flag.
    public var hasSideSwitched: Bool

    /// Only meaningful for `.rally(freeze: true)` games, where it gates
    /// whether a qualifying score can end the game (see
    /// `PickleballGame.gameWinner`). Side-out play always sets this `true`
    /// regardless of who actually won the rally, so it must not be read for
    /// any other purpose under side-out scoring.
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

    private enum CodingKeys: String, CodingKey {
        case teamAScore
        case teamBScore
        case servingTeam
        case serverNumber
        case teamATimeoutsRemaining
        case teamBTimeoutsRemaining
        case hasSideSwitched
        case lastPointWonWhileServing
    }
}
