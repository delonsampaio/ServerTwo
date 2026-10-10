import Observation
import SwiftData
import PickleballKit
import Foundation

enum ActiveMatchControllerError: Error, Equatable {
    case noActiveMatch
}

/// Owns the one live `PickleballMatch`, wraps `MatchRepository`, and is the
/// single place that persists an in-progress snapshot after every mutation.
/// `@MainActor` because this is the first real UI call site for
/// `PickleballMatch`/`MatchRepository` — see this plan's Global Constraints.
@MainActor
@Observable
final class ActiveMatchController {
    private enum Keys {
        static let proUnlocked = "mockProUnlocked"
        static let activeTeamAName = "activeMatchTeamAName"
        static let activeTeamBName = "activeMatchTeamBName"
    }

    private(set) var match: PickleballMatch?
    private(set) var teamAName: String = "Team A"
    private(set) var teamBName: String = "Team B"
    private var startedAt: Date?
    private var teamAPlayers: [SavedPlayer] = []
    private var teamBPlayers: [SavedPlayer] = []

    private let repository: MatchRepository
    private let userDefaults: UserDefaults

    var proUnlocked: Bool {
        didSet { userDefaults.set(proUnlocked, forKey: Keys.proUnlocked) }
    }

    /// How many full matches a free user may complete before `canStartNewMatch`
    /// turns false. Not `let`: XCUITests override this (see `MyApp`'s
    /// `applyTestOverridesIfNeeded`). The demo gate lives entirely here, at
    /// match-start — `PickleballMatch` is always given a `nil` point cap
    /// (below), so a free user's match is never interrupted mid-game; they
    /// play it all the way to a real finish, see it in History, and only
    /// hit the paywall when trying to start another one.
    var demoMatchLimit: Int = 1

    /// True if the user may start a new match: either they're unlocked, or
    /// they haven't yet used up `demoMatchLimit` completed matches.
    var canStartNewMatch: Bool {
        guard !proUnlocked else { return true }
        let completedCount = (try? repository.fetchMatchHistory().count) ?? 0
        return completedCount < demoMatchLimit
    }

    init(modelContext: ModelContext, userDefaults: UserDefaults = .standard) {
        self.repository = MatchRepository(modelContext: modelContext)
        self.userDefaults = userDefaults
        self.proUnlocked = userDefaults.bool(forKey: Keys.proUnlocked)
        resumeIfNeeded()
    }

    func resumeIfNeeded() {
        guard match == nil else { return }
        guard let resumed = try? repository.loadInProgressMatch(proUnlocked: proUnlocked, demoPointCap: nil) else { return }
        match = resumed.match
        startedAt = resumed.startedAt
        teamAName = userDefaults.string(forKey: Keys.activeTeamAName) ?? "Team A"
        teamBName = userDefaults.string(forKey: Keys.activeTeamBName) ?? "Team B"
    }

    func startNewMatch(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        firstServingTeam: Team,
        teamAName: String,
        teamBName: String,
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = []
    ) {
        self.teamAName = teamAName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team A" : teamAName
        self.teamBName = teamBName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team B" : teamBName
        self.teamAPlayers = teamAPlayers
        self.teamBPlayers = teamBPlayers
        userDefaults.set(self.teamAName, forKey: Keys.activeTeamAName)
        userDefaults.set(self.teamBName, forKey: Keys.activeTeamBName)

        match = PickleballMatch(
            configuration: configuration,
            matchFormat: matchFormat,
            firstServingTeam: firstServingTeam,
            proUnlocked: proUnlocked,
            demoPointCap: nil
        )
        startedAt = Date()
        persistSnapshot()
    }

    func recordPoint(for team: Team) {
        match?.recordPoint(for: team)
        persistSnapshot()
    }

    func undo() {
        match?.undo()
        persistSnapshot()
    }

    func correctScore(team: Team, to newScore: Int) {
        match?.correctScore(team: team, to: newScore)
        persistSnapshot()
    }

    @discardableResult
    func requestTimeout(for team: Team) -> Bool {
        guard let match else { return false }
        let started = match.requestTimeout(for: team)
        if started { persistSnapshot() }
        return started
    }

    func unlockPro() {
        proUnlocked = true
        match?.unlockPro()
        persistSnapshot()
    }

    @discardableResult
    func finishMatch() throws -> MatchRecord {
        guard let match, let startedAt else {
            throw ActiveMatchControllerError.noActiveMatch
        }
        let record = try repository.saveCompletedMatch(
            match,
            teamAName: teamAName,
            teamBName: teamBName,
            startedAt: startedAt,
            teamAPlayers: teamAPlayers,
            teamBPlayers: teamBPlayers
        )
        self.match = nil
        self.startedAt = nil
        self.teamAPlayers = []
        self.teamBPlayers = []
        userDefaults.removeObject(forKey: Keys.activeTeamAName)
        userDefaults.removeObject(forKey: Keys.activeTeamBName)
        return record
    }

    /// Test-only: discards any live/resumed match and its persisted
    /// snapshot, so a UI test starts from a guaranteed-clean slate
    /// regardless of what a previous run or app session left behind.
    func clearAnyInProgressMatchForTesting() {
        match = nil
        startedAt = nil
        try? repository.clearInProgressSnapshot()
    }

    /// Test-only: wipes completed match history, so `canStartNewMatch`'s
    /// count against `demoMatchLimit` starts from zero on every UI test run
    /// regardless of what previous runs saved to the real on-device store.
    func clearAllMatchHistoryForTesting() {
        try? repository.deleteAllMatchHistory()
    }

    private func persistSnapshot() {
        guard let match, let startedAt else { return }
        try? repository.saveInProgressSnapshot(for: match, startedAt: startedAt)
    }
}
