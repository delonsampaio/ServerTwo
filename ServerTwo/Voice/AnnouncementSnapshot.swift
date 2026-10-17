import PickleballKit

/// The facts `AnnouncementPlanner` needs about the live match, captured as a
/// plain Equatable value so `ScoringView` can observe it with a single
/// `.onChange` and compare the previous and new state.
struct AnnouncementSnapshot: Equatable {
    /// `completedGames.count`: rises when a game finishes, falls when an undo
    /// reopens the previous game.
    var gameIndex: Int
    var teamAScore: Int
    var teamBScore: Int
    var servingTeam: Team
    var serverNumber: ServerNumber
    var hasSideSwitched: Bool
    var teamATimeoutsRemaining: Int
    var teamBTimeoutsRemaining: Int
    var teamAGamesWon: Int
    var teamBGamesWon: Int
    var isMatchOver: Bool
    /// Final score and winner of the most recently completed game, if any.
    var lastCompleted: CompletedGame?
    /// `currentGame.history.count`: rises with every forward move (point,
    /// timeout, correction) and falls on undo within a game, so the planner can
    /// tell "Side out." (a forward move) from an undo that restored the serve.
    /// Across a game boundary it resets or is restored; the planner never reads
    /// it there because the game-index branches return first.
    var moveCount: Int

    struct CompletedGame: Equatable {
        var teamAScore: Int
        var teamBScore: Int
        var winner: Team?
    }
}

extension AnnouncementSnapshot {
    init(match: PickleballMatch) {
        let state = match.currentGame.state
        self.init(
            gameIndex: match.completedGames.count,
            teamAScore: state.teamAScore,
            teamBScore: state.teamBScore,
            servingTeam: state.servingTeam,
            serverNumber: state.serverNumber,
            hasSideSwitched: state.hasSideSwitched,
            teamATimeoutsRemaining: state.teamATimeoutsRemaining,
            teamBTimeoutsRemaining: state.teamBTimeoutsRemaining,
            teamAGamesWon: match.gamesWon(for: .teamA),
            teamBGamesWon: match.gamesWon(for: .teamB),
            isMatchOver: match.isMatchOver,
            lastCompleted: match.completedGames.last.map {
                CompletedGame(
                    teamAScore: $0.state.teamAScore,
                    teamBScore: $0.state.teamBScore,
                    winner: $0.gameWinner
                )
            },
            moveCount: match.currentGame.history.count
        )
    }
}
