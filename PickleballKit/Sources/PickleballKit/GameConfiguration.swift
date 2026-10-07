public struct GameConfiguration: Codable, Sendable, Equatable {
    public var playMode: PlayMode
    public var scoringFormat: ScoringFormat
    public var winningScore: WinningScore
    public var winByTwo: Bool
    public var timeoutsPerTeam: Int

    public init(
        playMode: PlayMode = .doubles,
        scoringFormat: ScoringFormat = .sideOut,
        winningScore: WinningScore = .eleven,
        winByTwo: Bool = true,
        timeoutsPerTeam: Int = 2
    ) {
        self.playMode = playMode
        self.scoringFormat = scoringFormat
        self.winningScore = winningScore
        self.winByTwo = winByTwo
        self.timeoutsPerTeam = timeoutsPerTeam
    }

    private enum CodingKeys: String, CodingKey {
        case playMode
        case scoringFormat
        case winningScore
        case winByTwo
        case timeoutsPerTeam
    }
}
