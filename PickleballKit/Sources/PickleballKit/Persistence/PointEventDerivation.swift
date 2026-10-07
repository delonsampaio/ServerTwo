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
/// timeouts and side-out rotations with no score change are correctly
/// excluded. A manual `correctScore` edit is NOT distinguished from a real
/// scored point: a correction that changes the score is logged as one
/// event carrying whatever delta the correction produced (which may not be
/// 1), and a correction that *lowers* a score produces no event at all.
/// This makes the derived log potentially non-monotonic or score-skipping
/// for a corrected game — known, deferred limitation (manual correction is
/// a dispute-resolution edge case, not the default flow); do not rely on
/// this log's event count to equal "points played" for a corrected game.
/// `GameRecord.teamAFinalScore`/`teamBFinalScore` (read directly from the
/// game's final state, not derived from this log) are unaffected and
/// remain correct for win/loss and points-for/against purposes.
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
