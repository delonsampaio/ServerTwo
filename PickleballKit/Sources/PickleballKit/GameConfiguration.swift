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

    /// Whether `teamA`/`teamB` represents a legal *completed* game's final
    /// score under this configuration's win condition — not merely "the
    /// win-by-2/winning-score thresholds are currently satisfied" (which
    /// live play never needs to distinguish from "and could only have
    /// gotten here through a legal sequence of single points," since
    /// `PickleballGame.recordPoint` physically cannot overshoot). An
    /// after-the-fact score entry (Quick Log) has no such guarantee, so this
    /// also rejects negative scores and impossible overtime margins (e.g.
    /// 15-10 in an 11-point win-by-2 game — the game would have already
    /// ended at 11-9 or 12-10).
    ///
    /// Deliberately does NOT evaluate `.rally(freeze: true)`'s "won on
    /// serve" rule, or constrain its overtime margin — both depend on live
    /// serve-sequence state this pure score check has no access to.
    /// `PickleballGame.gameWinner` layers the serve-order check on top for
    /// live play; this is for validating an already-known final score with
    /// no serve history (e.g. Quick Log).
    public func isCompletedGameScore(teamA: Int, teamB: Int) -> Bool {
        guard teamA >= 0, teamB >= 0, teamA != teamB else { return false }
        let winner = max(teamA, teamB)
        let loser = min(teamA, teamB)
        guard winner >= winningScore.rawValue else { return false }
        if winByTwo, winner - loser < 2 { return false }
        guard winner > winningScore.rawValue else { return true }  // not overtime — above checks suffice
        if case .rally(let freeze) = scoringFormat, freeze { return true }  // see doc comment
        return winByTwo && (winner - loser == 2)
    }

    /// Whether `teamA`/`teamB` is a score live play could actually produce:
    /// a legal completed final (see `isCompletedGameScore`) or a legal
    /// in-progress score. Used to gate manual score correction, so a
    /// correction can never leave a game that ends mid-edit or can never end
    /// by scoring more points.
    ///
    /// `.rally(freeze: true)` is deliberately permissive for scores above the
    /// target — same stance as `isCompletedGameScore`, since freeze's margin
    /// depends on serve-sequence state this pure check can't see.
    public func isReachableGameScore(teamA: Int, teamB: Int) -> Bool {
        guard teamA >= 0, teamB >= 0 else { return false }
        if isCompletedGameScore(teamA: teamA, teamB: teamB) { return true }
        if max(teamA, teamB) < winningScore.rawValue { return true }
        if case .rally(let freeze) = scoringFormat, freeze { return true }
        // At/above the target in a non-freeze game, play only continues when
        // win-by-2 is on and the score is tied or one ahead.
        return winByTwo && abs(teamA - teamB) <= 1
    }
}
