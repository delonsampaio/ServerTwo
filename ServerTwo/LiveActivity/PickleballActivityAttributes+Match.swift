import PickleballKit

// App target only: the extension never builds a ContentState from a live match,
// so this mapping stays out of the shared attributes file (which would
// otherwise drag PickleballKit and SwiftData into the extension).

extension PickleballActivityAttributes.ContentState {
    /// Pure snapshot of what the Lock Screen needs from a live match.
    init(match: PickleballMatch) {
        let state = match.currentGame.state
        self.init(
            teamAScore: state.teamAScore,
            teamBScore: state.teamBScore,
            teamAGamesWon: match.gamesWon(for: .teamA),
            teamBGamesWon: match.gamesWon(for: .teamB),
            servingTeamRawValue: state.servingTeam.rawValue,
            // Same rule as the in-app SERVER 1/2 badge (`ServingBadge`): only
            // doubles side-out scoring has a numbered server.
            serverNumber: match.configuration.playMode == .doubles && match.configuration.scoringFormat == .sideOut
                ? state.serverNumber.rawValue
                : nil,
            isMatchOver: match.isMatchOver
        )
    }
}

extension PickleballActivityAttributes {
    /// `teamAName`/`teamBName` are the names the app already resolved (blank
    /// names fall back to "Team A"/"Team B" at match start).
    init(match: PickleballMatch, teamAName: String, teamBName: String) {
        self.init(
            teamAName: teamAName,
            teamBName: teamBName,
            matchFormatSummary: match.configuration.summaryText(matchFormat: match.matchFormat),
            // The point score resets to 0-0 between games, so in a multi-game
            // match the tally is what explains a sudden 0-0.
            showsGamesWon: match.matchFormat != .bestOfOne
        )
    }
}
