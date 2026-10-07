import Foundation

public struct MatchSnapshot: Codable, Equatable, Sendable {
    public struct GameSnapshot: Codable, Equatable, Sendable {
        public var state: GameState
        public var history: [GameState]

        public init(state: GameState, history: [GameState]) {
            self.state = state
            self.history = history
        }
    }

    public var startedAt: Date
    public var configuration: GameConfiguration
    public var matchFormat: MatchFormat
    public var completedGames: [GameSnapshot]
    public var currentGame: GameSnapshot
    public var gamesWonTeamA: Int
    public var gamesWonTeamB: Int
    public var currentGameIsCounted: Bool

    public init(
        startedAt: Date,
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        completedGames: [GameSnapshot],
        currentGame: GameSnapshot,
        gamesWonTeamA: Int,
        gamesWonTeamB: Int,
        currentGameIsCounted: Bool
    ) {
        self.startedAt = startedAt
        self.configuration = configuration
        self.matchFormat = matchFormat
        self.completedGames = completedGames
        self.currentGame = currentGame
        self.gamesWonTeamA = gamesWonTeamA
        self.gamesWonTeamB = gamesWonTeamB
        self.currentGameIsCounted = currentGameIsCounted
    }
}

extension PickleballMatch {
    /// `startedAt` is caller-supplied (the match engine doesn't track wall-clock
    /// time) so it survives a crash-recovery round-trip for later use when the
    /// match is eventually saved to history.
    public func snapshot(startedAt: Date) -> MatchSnapshot {
        MatchSnapshot(
            startedAt: startedAt,
            configuration: configuration,
            matchFormat: matchFormat,
            completedGames: completedGames.map {
                MatchSnapshot.GameSnapshot(state: $0.state, history: $0.history)
            },
            currentGame: MatchSnapshot.GameSnapshot(state: currentGame.state, history: currentGame.history),
            gamesWonTeamA: gamesWon(for: .teamA),
            gamesWonTeamB: gamesWon(for: .teamB),
            currentGameIsCounted: currentGameIsCounted
        )
    }

    /// `proUnlocked`/`demoPointCap` are caller-supplied, sourced from the
    /// live entitlement at resume time — not read from the snapshot. This
    /// keeps the demo-cap gate's single source of truth intact (Spec §1):
    /// a snapshot taken before a purchase must not resume into a stale
    /// paywalled state once the user has actually unlocked Pro.
    public convenience init(resuming snapshot: MatchSnapshot, proUnlocked: Bool, demoPointCap: Int?) {
        let completed = snapshot.completedGames.map { gameSnapshot in
            PickleballGame(
                configuration: snapshot.configuration,
                state: gameSnapshot.state,
                history: gameSnapshot.history,
                proUnlocked: proUnlocked,
                demoPointCap: demoPointCap
            )
        }
        let current = PickleballGame(
            configuration: snapshot.configuration,
            state: snapshot.currentGame.state,
            history: snapshot.currentGame.history,
            proUnlocked: proUnlocked,
            demoPointCap: demoPointCap
        )
        self.init(
            configuration: snapshot.configuration,
            matchFormat: snapshot.matchFormat,
            completedGames: completed,
            currentGame: current,
            gamesWon: [.teamA: snapshot.gamesWonTeamA, .teamB: snapshot.gamesWonTeamB],
            currentGameIsCounted: snapshot.currentGameIsCounted
        )
    }
}
