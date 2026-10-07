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
        proUnlocked: Bool,
        demoPointCap: Int?
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
        if let lastCompleted = completedGames.last, lastCompleted === currentGame {
            // The match ended on this exact game, so currentGame was never
            // reassigned to a new object (see recordPoint) and is aliased
            // with completedGames.last. Undoing the match-deciding point
            // must also reverse the win count, not just revert the score.
            completedGames.removeLast()
            if let winner = currentGame.gameWinner {
                gamesWon[winner, default: 0] -= 1
            }
            currentGame.undo()
            return
        }
        if currentGame.canUndo {
            currentGame.undo()
            return
        }
        guard let previousGame = completedGames.popLast() else { return }
        if let winner = previousGame.gameWinner {
            gamesWon[winner, default: 0] -= 1
        }
        currentGame = previousGame
        currentGame.undo()
    }

    public func correctScore(team: Team, to newScore: Int) {
        let wasCounted = completedGames.last === currentGame
        let previousWinner = wasCounted ? currentGame.gameWinner : nil

        currentGame.correctScore(team: team, to: newScore)

        let newWinner = currentGame.gameWinner

        guard previousWinner != newWinner else { return }

        if let previousWinner {
            gamesWon[previousWinner, default: 0] -= 1
            if wasCounted {
                completedGames.removeLast()
            }
        }

        if let newWinner {
            gamesWon[newWinner, default: 0] += 1
            completedGames.append(currentGame)
            if !isMatchOver {
                currentGame = PickleballGame(
                    configuration: configuration,
                    firstServingTeam: newWinner,
                    proUnlocked: currentGame.proUnlocked,
                    demoPointCap: currentGame.demoPointCap
                )
            }
        }
    }

    @discardableResult
    public func requestTimeout(for team: Team) -> Bool {
        currentGame.requestTimeout(for: team)
    }

    public var isPaywalled: Bool {
        currentGame.isPaywalled
    }

    public func unlockPro() {
        currentGame.unlockPro()
    }

    public func gamesWon(for team: Team) -> Int {
        gamesWon[team, default: 0]
    }
}
