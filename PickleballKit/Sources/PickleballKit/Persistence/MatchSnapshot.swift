public struct MatchSnapshot: Codable, Equatable, Sendable {
    public struct GameSnapshot: Codable, Equatable, Sendable {
        public var state: GameState
        public var history: [GameState]

        public init(state: GameState, history: [GameState]) {
            self.state = state
            self.history = history
        }
    }

    public var configuration: GameConfiguration
    public var matchFormat: MatchFormat
    public var proUnlocked: Bool
    public var demoPointCap: Int?
    public var completedGames: [GameSnapshot]
    public var currentGame: GameSnapshot
    public var gamesWonTeamA: Int
    public var gamesWonTeamB: Int

    public init(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        proUnlocked: Bool,
        demoPointCap: Int?,
        completedGames: [GameSnapshot],
        currentGame: GameSnapshot,
        gamesWonTeamA: Int,
        gamesWonTeamB: Int
    ) {
        self.configuration = configuration
        self.matchFormat = matchFormat
        self.proUnlocked = proUnlocked
        self.demoPointCap = demoPointCap
        self.completedGames = completedGames
        self.currentGame = currentGame
        self.gamesWonTeamA = gamesWonTeamA
        self.gamesWonTeamB = gamesWonTeamB
    }
}

extension PickleballMatch {
    public var snapshot: MatchSnapshot {
        MatchSnapshot(
            configuration: configuration,
            matchFormat: matchFormat,
            proUnlocked: currentGame.proUnlocked,
            demoPointCap: currentGame.demoPointCap,
            completedGames: completedGames.map {
                MatchSnapshot.GameSnapshot(state: $0.state, history: $0.history)
            },
            currentGame: MatchSnapshot.GameSnapshot(state: currentGame.state, history: currentGame.history),
            gamesWonTeamA: gamesWon(for: .teamA),
            gamesWonTeamB: gamesWon(for: .teamB)
        )
    }

    public convenience init(resuming snapshot: MatchSnapshot) {
        let completed = snapshot.completedGames.map { gameSnapshot in
            PickleballGame(
                configuration: snapshot.configuration,
                state: gameSnapshot.state,
                history: gameSnapshot.history,
                proUnlocked: snapshot.proUnlocked,
                demoPointCap: snapshot.demoPointCap
            )
        }
        let current = PickleballGame(
            configuration: snapshot.configuration,
            state: snapshot.currentGame.state,
            history: snapshot.currentGame.history,
            proUnlocked: snapshot.proUnlocked,
            demoPointCap: snapshot.demoPointCap
        )
        self.init(
            configuration: snapshot.configuration,
            matchFormat: snapshot.matchFormat,
            completedGames: completed,
            currentGame: current,
            gamesWon: [.teamA: snapshot.gamesWonTeamA, .teamB: snapshot.gamesWonTeamB]
        )
    }
}
