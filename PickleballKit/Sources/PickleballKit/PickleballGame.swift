import Observation

@Observable
public final class PickleballGame {
    public let configuration: GameConfiguration
    public private(set) var state: GameState
    public private(set) var proUnlocked: Bool
    public let demoPointCap: Int?

    private var history: [GameState] = []

    public init(
        configuration: GameConfiguration,
        firstServingTeam: Team,
        proUnlocked: Bool = true,
        demoPointCap: Int? = nil
    ) {
        self.configuration = configuration
        self.proUnlocked = proUnlocked
        self.demoPointCap = demoPointCap

        let startingServerNumber: ServerNumber = configuration.playMode == .doubles ? .two : .one
        self.state = GameState(
            teamAScore: 0,
            teamBScore: 0,
            servingTeam: firstServingTeam,
            serverNumber: startingServerNumber,
            teamATimeoutsRemaining: configuration.timeoutsPerTeam,
            teamBTimeoutsRemaining: configuration.timeoutsPerTeam,
            hasSideSwitched: false,
            lastPointWonWhileServing: true
        )
    }

    public var canUndo: Bool { !history.isEmpty }

    public var isGameOver: Bool { gameWinner != nil }

    public var gameWinner: Team? {
        let a = state.teamAScore
        let b = state.teamBScore
        let target = configuration.winningScore.rawValue
        guard max(a, b) >= target else { return nil }
        if configuration.winByTwo && abs(a - b) < 2 { return nil }
        let leader: Team = a > b ? .teamA : .teamB
        if case .rally(let freeze) = configuration.scoringFormat, freeze {
            guard state.lastPointWonWhileServing else { return nil }
        }
        return leader
    }

    public func recordPoint(for scoringTeam: Team) {
        guard !isGameOver else { return }
        history.append(state)

        let previousServingTeam = state.servingTeam

        switch configuration.scoringFormat {
        case .sideOut:
            recordSideOutPoint(for: scoringTeam)
        case .rally:
            recordRallyPoint(for: scoringTeam, previousServingTeam: previousServingTeam)
        }

        checkSideSwitch()
    }

    private func recordSideOutPoint(for scoringTeam: Team) {
        if scoringTeam == state.servingTeam {
            addScore(to: scoringTeam)
            state.lastPointWonWhileServing = true
            return
        }
        // Side-out event.
        guard configuration.playMode == .doubles else {
            // Singles has only one server per team — any lost rally while
            // receiving is an immediate side-out.
            state.servingTeam = scoringTeam
            state.serverNumber = .one
            return
        }
        // Doubles: Server 1 losing advances to Server 2 without changing
        // the serving team; Server 2 losing fully sides out.
        switch state.serverNumber {
        case .one:
            state.serverNumber = .two
        case .two:
            state.servingTeam = scoringTeam
            state.serverNumber = .one
        }
    }

    private func recordRallyPoint(for scoringTeam: Team, previousServingTeam: Team) {
        addScore(to: scoringTeam)
        state.lastPointWonWhileServing = (scoringTeam == previousServingTeam)
        state.servingTeam = scoringTeam
        state.serverNumber = .one
    }

    private func addScore(to team: Team) {
        if team == .teamA {
            state.teamAScore += 1
        } else {
            state.teamBScore += 1
        }
    }

    private func checkSideSwitch() {
        guard !state.hasSideSwitched else { return }
        let threshold = configuration.winningScore.sideSwitchThreshold
        if state.teamAScore >= threshold || state.teamBScore >= threshold {
            state.hasSideSwitched = true
        }
    }

    @discardableResult
    public func requestTimeout(for team: Team) -> Bool {
        let remaining = state.timeoutsRemaining(for: team)
        guard remaining > 0 else { return false }
        history.append(state)
        if team == .teamA {
            state.teamATimeoutsRemaining -= 1
        } else {
            state.teamBTimeoutsRemaining -= 1
        }
        return true
    }
}
