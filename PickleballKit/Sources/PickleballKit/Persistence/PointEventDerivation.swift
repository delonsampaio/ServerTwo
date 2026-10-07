public struct DerivedPointEvent: Equatable, Sendable {
    public let sequenceNumber: Int
    public let scoringTeam: Team
    public let teamAScoreAfter: Int
    public let teamBScoreAfter: Int

    public init(sequenceNumber: Int, scoringTeam: Team, teamAScoreAfter: Int, teamBScoreAfter: Int) {
        self.sequenceNumber = sequenceNumber
        self.scoringTeam = scoringTeam
        self.teamAScoreAfter = teamAScoreAfter
        self.teamBScoreAfter = teamBScoreAfter
    }
}

/// Derives a point-by-point log from a game's state history. Only
/// transitions where a team's score actually increased become events —
/// timeouts, side-out rotations with no score change, and no-op corrections
/// are not "scored points" and are intentionally excluded.
public func derivePointEvents(history: [GameState], finalState: GameState) -> [DerivedPointEvent] {
    let allStates = history + [finalState]
    guard allStates.count > 1 else { return [] }

    var events: [DerivedPointEvent] = []
    var sequenceNumber = 0
    for index in 1..<allStates.count {
        let before = allStates[index - 1]
        let after = allStates[index]

        let scoringTeam: Team
        if after.teamAScore > before.teamAScore {
            scoringTeam = .teamA
        } else if after.teamBScore > before.teamBScore {
            scoringTeam = .teamB
        } else {
            continue
        }

        sequenceNumber += 1
        events.append(DerivedPointEvent(
            sequenceNumber: sequenceNumber,
            scoringTeam: scoringTeam,
            teamAScoreAfter: after.teamAScore,
            teamBScoreAfter: after.teamBScore
        ))
    }
    return events
}
