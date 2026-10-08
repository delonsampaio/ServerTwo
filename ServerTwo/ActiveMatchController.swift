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

    private let repository: MatchRepository
    private let userDefaults: UserDefaults

    var proUnlocked: Bool {
        didSet { userDefaults.set(proUnlocked, forKey: Keys.proUnlocked) }
    }

    /// Not `let`: Phase 3's paywall is a stub pending Phase 4's real StoreKit
    /// wiring, and XCUITests override this to a small number so a test
    /// doesn't need 11 real taps to reach the cap (see `MyApp`'s
    /// `applyTestOverridesIfNeeded`).
    var demoPointCap: Int = 5

    init(modelContext: ModelContext, userDefaults: UserDefaults = .standard) {
        self.repository = MatchRepository(modelContext: modelContext)
        self.userDefaults = userDefaults
        self.proUnlocked = userDefaults.bool(forKey: Keys.proUnlocked)
        resumeIfNeeded()
    }

    func resumeIfNeeded() {
        guard match == nil else { return }
        guard let resumed = try? repository.loadInProgressMatch(proUnlocked: proUnlocked, demoPointCap: demoPointCap) else { return }
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
        teamBName: String
    ) {
        self.teamAName = teamAName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team A" : teamAName
        self.teamBName = teamBName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team B" : teamBName
        userDefaults.set(self.teamAName, forKey: Keys.activeTeamAName)
        userDefaults.set(self.teamBName, forKey: Keys.activeTeamBName)

        match = PickleballMatch(
            configuration: configuration,
            matchFormat: matchFormat,
            firstServingTeam: firstServingTeam,
            proUnlocked: proUnlocked,
            demoPointCap: demoPointCap
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
            startedAt: startedAt
        )
        self.match = nil
        self.startedAt = nil
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

    private func persistSnapshot() {
        guard let match, let startedAt else { return }
        try? repository.saveInProgressSnapshot(for: match, startedAt: startedAt)
    }
}
