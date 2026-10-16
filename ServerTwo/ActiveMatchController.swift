import Observation
import SwiftData
import PickleballKit
import Foundation

enum ActiveMatchControllerError: Error, Equatable {
    case noActiveMatch
}

/// A live match's full in-memory state — bundled together (rather than kept
/// as separate optional properties on the controller) so `finishMatch()` and
/// `persistSnapshot()` can't observe a half-populated combination, e.g. a
/// `match` with no `startedAt`.
private struct ActiveMatchInfo {
    let match: PickleballMatch
    let startedAt: Date
    let teamAName: String
    let teamBName: String
    /// Ids, never `SavedPlayer` objects — see `PendingMatchSetup`'s doc
    /// comment for why.
    let teamAPlayerIDs: [UUID]
    let teamBPlayerIDs: [UUID]
}

/// The match lifecycle end to end: nothing going on, a setup staged but
/// awaiting the first-serve coin flip, or a live scoring match. Modeled as
/// one enum rather than independent optionals (`match: PickleballMatch?`
/// alongside `pendingSetup: PendingMatchSetup?`) so an impossible
/// combination — both set at once, or a match with no start time — simply
/// can't be represented.
private enum MatchLifecycleState {
    case idle
    case staged(PendingMatchSetup)
    case active(ActiveMatchInfo)
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

    private var lifecycleState: MatchLifecycleState = .idle

    var match: PickleballMatch? {
        if case .active(let info) = lifecycleState { return info.match }
        return nil
    }

    /// Non-nil exactly when a match has been staged (Setup's "Start Match"
    /// was tapped) but the first-serve coin flip hasn't resolved yet — the
    /// signal `RootTabView` uses to show the coin-flip screen instead of
    /// either Setup or live scoring.
    var pendingMatchSetup: PendingMatchSetup? {
        if case .staged(let setup) = lifecycleState { return setup }
        return nil
    }

    var teamAName: String {
        if case .active(let info) = lifecycleState { return info.teamAName }
        return "Team A"
    }

    var teamBName: String {
        if case .active(let info) = lifecycleState { return info.teamBName }
        return "Team B"
    }

    /// Set by either cancel method, consumed once by `MatchSetupView` to
    /// restore the names/rules of whatever was just canceled — cancelling
    /// is usually "wrong setting" or "redo the coin flip," not "I never
    /// want to play these people," so retyping everyone from scratch would
    /// be exactly the friction Rematch/Quick Start already exist to avoid.
    private(set) var lastCanceledSetup: PendingMatchSetup?

    func clearLastCanceledSetup() {
        lastCanceledSetup = nil
    }

    /// Positional with `match?.completedGames` — index `i` is when game
    /// `i`'s winning point was recorded. `nil` entries are games that
    /// completed before this session's own timestamp capture began (a
    /// crash-resumed match's pre-crash games — see `resumeIfNeeded`
    /// below), never a placeholder for "forgot to record." Never
    /// persisted to `GameRecord`/`MatchRecord` directly — `finishMatch()`
    /// hands the whole array to `saveCompletedMatch`, which is the only
    /// place it's written to disk.
    private(set) var gameCompletionDates: [Date?] = []

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
        guard case .idle = lifecycleState else { return }
        guard let resumed = try? repository.loadInProgressMatch(proUnlocked: proUnlocked, demoPointCap: nil) else { return }
        // A crash/relaunch during the coin-flip screen (staged, not yet
        // active) loses that staged setup — only an active match's snapshot
        // is ever persisted, same accepted trade-off as this feature's
        // design. Player attribution is similarly not recoverable across a
        // resume — matches `teamAPlayerIDs`/`teamBPlayerIDs`' pre-existing
        // crash-resume limitation.
        lifecycleState = .active(ActiveMatchInfo(
            match: resumed.match,
            startedAt: resumed.startedAt,
            teamAName: userDefaults.string(forKey: Keys.activeTeamAName) ?? "Team A",
            teamBName: userDefaults.string(forKey: Keys.activeTeamBName) ?? "Team B",
            teamAPlayerIDs: [],
            teamBPlayerIDs: []
        ))
        gameCompletionDates = Array(repeating: nil, count: resumed.match.completedGames.count)
    }

    /// Captures everything Setup decided except who serves first —
    /// `PickleballMatch` can't be created without that. `RootTabView` shows
    /// the coin-flip screen whenever `pendingMatchSetup` is non-nil; that
    /// screen calls `confirmFirstServe` once a result is in.
    func stageMatch(_ setup: PendingMatchSetup) {
        lifecycleState = .staged(setup)
    }

    /// Backs out of a staged (not-yet-flipped) match, e.g. the user wants
    /// to go back and change something in Setup. Nothing was ever
    /// persisted at this point, so this is a pure in-memory reset.
    func cancelPendingMatch() {
        guard case .staged(let setup) = lifecycleState else { return }
        lastCanceledSetup = setup
        lifecycleState = .idle
    }

    /// Turns a staged setup into a real, scoring `PickleballMatch` — called
    /// once the coin flip (or a manual "Team A/B Won Spin" override)
    /// determines who serves first. A no-op if nothing is staged.
    func confirmFirstServe(_ firstServingTeam: Team) {
        guard case .staged(let setup) = lifecycleState else { return }
        userDefaults.set(setup.resolvedTeamAName, forKey: Keys.activeTeamAName)
        userDefaults.set(setup.resolvedTeamBName, forKey: Keys.activeTeamBName)

        let match = PickleballMatch(
            configuration: setup.configuration,
            matchFormat: setup.matchFormat,
            firstServingTeam: firstServingTeam,
            proUnlocked: proUnlocked,
            demoPointCap: nil
        )
        lifecycleState = .active(ActiveMatchInfo(
            match: match,
            startedAt: Date(),
            teamAName: setup.resolvedTeamAName,
            teamBName: setup.resolvedTeamBName,
            teamAPlayerIDs: setup.teamAPlayerIDs,
            teamBPlayerIDs: setup.teamBPlayerIDs
        ))
        gameCompletionDates = []
        persistSnapshot()
    }

    func recordPoint(for team: Team) {
        match?.recordPoint(for: team)
        syncGameCompletionDates()
        persistSnapshot()
    }

    func undo() {
        match?.undo()
        syncGameCompletionDates()
        persistSnapshot()
    }

    func correctScore(team: Team, to newScore: Int) {
        match?.correctScore(team: team, to: newScore)
        syncGameCompletionDates()
        persistSnapshot()
    }

    func correctScores(teamA: Int, teamB: Int) {
        match?.correctScores(teamA: teamA, teamB: teamB)
        syncGameCompletionDates()
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
        guard case .active(let info) = lifecycleState else {
            throw ActiveMatchControllerError.noActiveMatch
        }
        let teamAPlayers = try repository.fetchSavedPlayers(ids: info.teamAPlayerIDs)
        let teamBPlayers = try repository.fetchSavedPlayers(ids: info.teamBPlayerIDs)
        let record = try repository.saveCompletedMatch(
            info.match,
            teamAName: info.teamAName,
            teamBName: info.teamBName,
            startedAt: info.startedAt,
            teamAPlayers: teamAPlayers,
            teamBPlayers: teamBPlayers,
            gameCompletionDates: gameCompletionDates
        )
        lifecycleState = .idle
        userDefaults.removeObject(forKey: Keys.activeTeamAName)
        userDefaults.removeObject(forKey: Keys.activeTeamBName)
        return record
    }

    /// Discards the live match entirely — nothing is saved to history, and
    /// its persisted snapshot is cleared so a relaunch doesn't resurrect
    /// it. A no-op if there's no active match. The only way out of a match
    /// before `finishMatch()` is otherwise possible; unlike
    /// `cancelPendingMatch()` (which backs out of an undecided coin flip
    /// that was never persisted), this has to actively clear real,
    /// already-persisted progress.
    func cancelActiveMatch() {
        guard case .active(let info) = lifecycleState else { return }
        lastCanceledSetup = PendingMatchSetup(
            configuration: info.match.configuration,
            matchFormat: info.match.matchFormat,
            teamAName: info.teamAName,
            teamBName: info.teamBName,
            teamAPlayerIDs: info.teamAPlayerIDs,
            teamBPlayerIDs: info.teamBPlayerIDs
        )
        lifecycleState = .idle
        gameCompletionDates = []
        userDefaults.removeObject(forKey: Keys.activeTeamAName)
        userDefaults.removeObject(forKey: Keys.activeTeamBName)
        try? repository.clearInProgressSnapshot()
    }

    /// Test-only: discards any live/resumed match or staged-but-unflipped
    /// setup, plus any persisted snapshot, so a UI test starts from a
    /// guaranteed-clean slate regardless of what a previous run or app
    /// session left behind.
    func clearAnyInProgressMatchForTesting() {
        lifecycleState = .idle
        try? repository.clearInProgressSnapshot()
    }

    /// Test-only: wipes completed match history AND every saved player
    /// (including whichever one is "Me"), so both `canStartNewMatch`'s
    /// count against `demoMatchLimit` and the player roster/suggestion
    /// chips start from zero on every UI test run — regardless of what
    /// previous runs left in the real on-device store. Without clearing
    /// players too, a "Me" flag set by an earlier run could silently
    /// persist and make a later run's own "mark as Me" step a no-op.
    func clearAllMatchHistoryForTesting() {
        try? repository.deleteAllMatchHistory()
        try? repository.deleteAllSavedPlayers()
    }

    /// Called from `recordPoint`/`undo`/`correctScores` only — each of
    /// those can move `completedGames.count` by exactly one in either
    /// direction, so a plain grow-by-one/shrink-by-one here is correct;
    /// it would NOT be correct if called from anywhere that could skip
    /// multiple games at once.
    private func syncGameCompletionDates() {
        guard let count = match?.completedGames.count else { return }
        if gameCompletionDates.count > count {
            gameCompletionDates.removeLast(gameCompletionDates.count - count)
        } else if gameCompletionDates.count < count {
            gameCompletionDates.append(contentsOf: Array(repeating: Date(), count: count - gameCompletionDates.count))
        }
    }

    private func persistSnapshot() {
        guard case .active(let info) = lifecycleState else { return }
        try? repository.saveInProgressSnapshot(for: info.match, startedAt: info.startedAt)
    }
}
