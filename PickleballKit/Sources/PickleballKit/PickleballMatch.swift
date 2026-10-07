import Observation

@Observable
public final class PickleballMatch {
    public let configuration: GameConfiguration
    public let matchFormat: MatchFormat
    public private(set) var completedGames: [PickleballGame] = []
    public private(set) var currentGame: PickleballGame
    public private(set) var gamesWon: [Team: Int] = [.teamA: 0, .teamB: 0]

    public init(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        firstServingTeam: Team,
        proUnlocked: Bool = true,
        demoPointCap: Int? = nil
    ) {
        self.configuration = configuration
        self.matchFormat = matchFormat
        self.currentGame = PickleballGame(
            configuration: configuration,
            firstServingTeam: firstServingTeam,
            proUnlocked: proUnlocked,
            demoPointCap: demoPointCap
        )
    }

    public var isMatchOver: Bool {
        gamesWon[.teamA, default: 0] >= matchFormat.gamesToWin
            || gamesWon[.teamB, default: 0] >= matchFormat.gamesToWin
    }

    public var matchWinner: Team? {
        if gamesWon[.teamA, default: 0] >= matchFormat.gamesToWin { return .teamA }
        if gamesWon[.teamB, default: 0] >= matchFormat.gamesToWin { return .teamB }
        return nil
    }

    public func recordPoint(for team: Team) {
        guard !isMatchOver else { return }
        currentGame.recordPoint(for: team)

        guard let winner = currentGame.gameWinner else { return }
        gamesWon[winner, default: 0] += 1
        completedGames.append(currentGame)

        guard !isMatchOver else { return }

        currentGame = PickleballGame(
            configuration: configuration,
            firstServingTeam: winner,
            proUnlocked: currentGame.proUnlocked,
            demoPointCap: currentGame.demoPointCap
        )
    }

    public func undo() {
        if currentGame.canUndo {
            currentGame.undo()
            return
        }
        guard let previousGame = completedGames.popLast() else { return }
        if let winner = previousGame.gameWinner {
            gamesWon[winner, default: 1] -= 1
        }
        currentGame = previousGame
        currentGame.undo()
    }
}
