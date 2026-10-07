import Observation

@Observable
public final class PickleballMatch {
    public let configuration: GameConfiguration
    public let matchFormat: MatchFormat
    public private(set) var completedGames: [PickleballGame] = []
    public private(set) var currentGame: PickleballGame
    public private(set) var gamesWon: [Team: Int] = [.teamA: 0, .teamB: 0]

    /// `true` when `currentGame`'s win is already reflected in `gamesWon`
    /// and `currentGame` is the same logical game as `completedGames.last`
    /// (the match ended on this exact game, so `recordPoint` never created
    /// a new one). This is tracked explicitly rather than inferred via
    /// `completedGames.last === currentGame` identity, because after a
    /// `MatchSnapshot` round-trip `completedGames` and `currentGame` are
    /// reconstructed as distinct objects even when they represent the same
    /// logical game — object identity does not survive serialization.
    /// Not `private`: Swift's `private` is file-scoped, and the
    /// `MatchSnapshot` round-trip extension (a different file in this same
    /// module) needs to read and set this. `internal` (the default) still
    /// keeps it hidden from anything importing PickleballKit as a package.
    var currentGameIsCounted: Bool

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
        self.currentGameIsCounted = false
    }

    /// Reconstructs a match from its already-reconstructed games — used by
    /// the persistence layer to resume a saved in-progress match after a
    /// crash or relaunch.
    public init(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        completedGames: [PickleballGame],
        currentGame: PickleballGame,
        gamesWon: [Team: Int],
        currentGameIsCounted: Bool
    ) {
        self.configuration = configuration
        self.matchFormat = matchFormat
        self.completedGames = completedGames
        self.currentGame = currentGame
        self.gamesWon = gamesWon
        self.currentGameIsCounted = currentGameIsCounted
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
        currentGameIsCounted = true

        guard !isMatchOver else { return }

        currentGame = PickleballGame(
            configuration: configuration,
            firstServingTeam: winner,
            proUnlocked: currentGame.proUnlocked,
            demoPointCap: currentGame.demoPointCap
        )
        currentGameIsCounted = false
    }

    public func undo() {
        if currentGameIsCounted {
            // The match ended on this exact game. Undoing the match-deciding
            // point must also reverse the win count, not just revert the
            // score.
            completedGames.removeLast()
            if let winner = currentGame.gameWinner {
                gamesWon[winner, default: 0] -= 1
            }
            currentGame.undo()
            currentGameIsCounted = false
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
        currentGameIsCounted = false
    }

    public func correctScore(team: Team, to newScore: Int) {
        let wasCounted = currentGameIsCounted
        let previousWinner = wasCounted ? currentGame.gameWinner : nil

        currentGame.correctScore(team: team, to: newScore)

        let newWinner = currentGame.gameWinner

        guard previousWinner != newWinner else { return }

        if let previousWinner {
            gamesWon[previousWinner, default: 0] -= 1
            if wasCounted {
                completedGames.removeLast()
                currentGameIsCounted = false
            }
        }

        if let newWinner {
            gamesWon[newWinner, default: 0] += 1
            completedGames.append(currentGame)
            currentGameIsCounted = true
            if !isMatchOver {
                currentGame = PickleballGame(
                    configuration: configuration,
                    firstServingTeam: newWinner,
                    proUnlocked: currentGame.proUnlocked,
                    demoPointCap: currentGame.demoPointCap
                )
                currentGameIsCounted = false
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
