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
    /// Not `private` only so the tests can assert on what is stored and cleared.
    enum Keys {
        /// Last known Pro entitlement, a seed for the first frame only (see
        /// `proUnlocked`). Not a purchase record: the old mock flag
        /// (`mockProUnlocked`) is deliberately not migrated into it.
        static let proEntitlementCache = "proEntitlementCache"
        static let activeTeamAName = "activeMatchTeamAName"
        static let activeTeamBName = "activeMatchTeamBName"
        /// `[String]` of `UUID.uuidString`, written next to the names so a
        /// resumed match can still be attributed to its saved players.
        static let activeTeamAPlayerIDs = "activeMatchTeamAPlayerIDs"
        static let activeTeamBPlayerIDs = "activeMatchTeamBPlayerIDs"
        /// `[String: Bool]` (game index as a string -> explicit swap flag) per
        /// team; see `StartingSideOverrides`.
        static let activeTeamAStartingSidesSwapped = "activeMatchTeamAStartingSidesSwapped"
        static let activeTeamBStartingSidesSwapped = "activeMatchTeamBStartingSidesSwapped"
        /// Completed matches ever saved on this device, never decreased. The
        /// demo gate reads this next to the history count so deleting the one
        /// free match cannot reopen the free demo.
        static let lifetimeCompletedMatchCount = "lifetimeCompletedMatchCount"
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

    /// Live, persisted display state for the partner positions on the score
    /// cards (see `StartingSideOverrides`). Observed, so the cards update when
    /// the correction sheet changes it.
    private var startingSideOverrides = StartingSideOverrides()

    private let repository: MatchRepository
    private let userDefaults: UserDefaults
    /// Mirrors the live match onto the Lock Screen / Dynamic Island. A `let`
    /// (never observed by SwiftUI) and fire-and-forget: it can never fail or
    /// delay scoring. The default is a no-op host; `MyApp` injects the real one.
    private let liveActivity: LiveActivityController

    /// Whether Pro is unlocked. `StoreManager` is the source of truth and pushes
    /// every refreshed entitlement in here; the value persisted below only
    /// seeds the first frame so a paying user never sees a locked flash while
    /// StoreKit is read at launch. Losing Pro mid-match (a refund) never
    /// interrupts the live match: this only gates starting the next one.
    var proUnlocked: Bool {
        didSet { userDefaults.set(proUnlocked, forKey: Keys.proEntitlementCache) }
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
    ///
    /// The count is the larger of the persisted lifetime counter and the
    /// history count. History alone would let a free user finish a match,
    /// delete it and play again; the counter alone would miss matches saved
    /// before the counter existed (it starts at 0 for them, so history decides).
    var canStartNewMatch: Bool {
        guard !proUnlocked else { return true }
        return effectiveCompletedMatchCount(historyCount: currentHistoryCount()) < demoMatchLimit
    }

    private func currentHistoryCount() -> Int {
        (try? repository.fetchMatchHistory().count) ?? 0
    }

    private func effectiveCompletedMatchCount(historyCount: Int) -> Int {
        max(userDefaults.integer(forKey: Keys.lifetimeCompletedMatchCount), historyCount)
    }

    /// Call after EVERY successful save of a completed match. `historyCountBeforeSave`
    /// is read before the save so the counter catches up with matches that
    /// predate it, and a delete followed by a new match keeps counting up
    /// rather than restarting from the (smaller) history.
    private func recordCompletedMatchSaved(historyCountBeforeSave: Int) {
        let stored = userDefaults.integer(forKey: Keys.lifetimeCompletedMatchCount)
        userDefaults.set(max(stored, historyCountBeforeSave) + 1, forKey: Keys.lifetimeCompletedMatchCount)
    }

    /// Quick Log's save, routed through the controller (instead of straight to
    /// the repository) so it counts toward the demo limit exactly like a
    /// finished live match.
    @discardableResult
    func saveQuickLoggedMatch(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        teamAName: String,
        teamBName: String,
        gameScores: [(teamA: Int, teamB: Int)],
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = [],
        completedAt: Date = Date()
    ) throws -> MatchRecord {
        let historyCountBeforeSave = currentHistoryCount()
        let record = try repository.saveQuickLoggedMatch(
            configuration: configuration,
            matchFormat: matchFormat,
            teamAName: teamAName,
            teamBName: teamBName,
            gameScores: gameScores,
            teamAPlayers: teamAPlayers,
            teamBPlayers: teamBPlayers,
            completedAt: completedAt
        )
        recordCompletedMatchSaved(historyCountBeforeSave: historyCountBeforeSave)
        return record
    }

    init(
        modelContext: ModelContext,
        userDefaults: UserDefaults = .standard,
        liveActivity: LiveActivityController = LiveActivityController(host: NoOpLiveActivityHost())
    ) {
        self.repository = MatchRepository(modelContext: modelContext)
        self.userDefaults = userDefaults
        self.liveActivity = liveActivity
        self.proUnlocked = userDefaults.bool(forKey: Keys.proEntitlementCache)
        resumeIfNeeded()
    }

    func resumeIfNeeded() {
        guard case .idle = lifecycleState else { return }
        guard let resumed = try? repository.loadInProgressMatch(proUnlocked: proUnlocked, demoPointCap: nil) else {
            // No match to resume: any Live Activity still showing is a stray
            // from a force quit between finishing a match and ending it.
            liveActivity.endAll()
            return
        }
        // A crash/relaunch during the coin-flip screen (staged, not yet
        // active) loses that staged setup — only an active match's snapshot
        // is ever persisted, same accepted trade-off as this feature's
        // design. The players ARE recovered (ids stored next to the names),
        // otherwise a match resumed after iOS killed the app between games
        // would be saved with no linked players and vanish from W/L, streaks,
        // chemistry and filters.
        let info = ActiveMatchInfo(
            match: resumed.match,
            startedAt: resumed.startedAt,
            teamAName: userDefaults.string(forKey: Keys.activeTeamAName) ?? "Team A",
            teamBName: userDefaults.string(forKey: Keys.activeTeamBName) ?? "Team B",
            teamAPlayerIDs: storedPlayerIDs(forKey: Keys.activeTeamAPlayerIDs),
            teamBPlayerIDs: storedPlayerIDs(forKey: Keys.activeTeamBPlayerIDs)
        )
        lifecycleState = .active(info)
        gameCompletionDates = Array(repeating: nil, count: resumed.match.completedGames.count)
        restoreStartingSideOverrides()
        liveActivity.resume(attributes: liveActivityAttributes(for: info), state: .init(match: info.match))
    }

    /// Invalid strings are ignored. A player deleted since the match began is
    /// fine: `fetchSavedPlayers(ids:)` skips ids it cannot find.
    private func storedPlayerIDs(forKey key: String) -> [UUID] {
        (userDefaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
    }

    /// Whether `team`'s partners started `gameIndex` in the swapped order (Player 2
    /// on the right). Display-only: it never touches the match or its history.
    func startingSidesSwapped(for team: Team, gameIndex: Int) -> Bool {
        startingSideOverrides.isSwapped(for: team, gameIndex: gameIndex)
    }

    /// Records an explicit setting for `gameIndex` (`match.completedGames.count`
    /// is the current one). Later games without their own entry inherit it.
    /// Persisted right away like the active names, so a relaunch keeps it.
    func setStartingSidesSwapped(_ value: Bool, for team: Team, gameIndex: Int) {
        guard case .active = lifecycleState else { return }
        startingSideOverrides.set(value, for: team, gameIndex: gameIndex)
        persistStartingSideOverrides()
    }

    /// Positions exist only in doubles SIDE-OUT scoring: in rally scoring the
    /// serve changes on every point, so a team's score no longer decides who
    /// stands where. `false` also when there is no match.
    var showsPartnerPositions: Bool {
        guard let configuration = match?.configuration else { return false }
        return configuration.playMode == .doubles && configuration.scoringFormat == .sideOut
    }

    /// The partner positions to show for `team` right now, or nil (singles,
    /// rally, or a name that does not split into two).
    func partnerPositions(for team: Team) -> PartnerPositions? {
        guard showsPartnerPositions, let match else { return nil }
        let gameIndex = match.completedGames.count
        return PartnerPositions.make(
            teamName: team == .teamA ? teamAName : teamBName,
            score: match.currentGame.state.score(for: team),
            swapped: startingSidesSwapped(for: team, gameIndex: gameIndex)
        )
    }

    private func persistStartingSideOverrides() {
        for (team, key) in [
            (Team.teamA, Keys.activeTeamAStartingSidesSwapped),
            (Team.teamB, Keys.activeTeamBStartingSidesSwapped),
        ] {
            let stored = startingSideOverrides.stored(for: team)
            if stored.isEmpty {
                userDefaults.removeObject(forKey: key)
            } else {
                userDefaults.set(stored, forKey: key)
            }
        }
    }

    private func restoreStartingSideOverrides() {
        startingSideOverrides = StartingSideOverrides(
            teamA: userDefaults.dictionary(forKey: Keys.activeTeamAStartingSidesSwapped) as? [String: Bool] ?? [:],
            teamB: userDefaults.dictionary(forKey: Keys.activeTeamBStartingSidesSwapped) as? [String: Bool] ?? [:]
        )
    }

    private func clearStoredActiveMatchDetails() {
        // Also here (not only in the lifecycle methods): finish, cancel and the
        // test reset all come through this one place, so a setting can never
        // leak into the next match.
        startingSideOverrides = StartingSideOverrides()
        userDefaults.removeObject(forKey: Keys.activeTeamAStartingSidesSwapped)
        userDefaults.removeObject(forKey: Keys.activeTeamBStartingSidesSwapped)
        userDefaults.removeObject(forKey: Keys.activeTeamAName)
        userDefaults.removeObject(forKey: Keys.activeTeamBName)
        userDefaults.removeObject(forKey: Keys.activeTeamAPlayerIDs)
        userDefaults.removeObject(forKey: Keys.activeTeamBPlayerIDs)
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
        // A new match starts from the default positions, whatever the previous
        // one left behind.
        startingSideOverrides = StartingSideOverrides()
        persistStartingSideOverrides()
        userDefaults.set(setup.resolvedTeamAName, forKey: Keys.activeTeamAName)
        userDefaults.set(setup.resolvedTeamBName, forKey: Keys.activeTeamBName)
        userDefaults.set(setup.teamAPlayerIDs.map(\.uuidString), forKey: Keys.activeTeamAPlayerIDs)
        userDefaults.set(setup.teamBPlayerIDs.map(\.uuidString), forKey: Keys.activeTeamBPlayerIDs)

        let match = PickleballMatch(
            configuration: setup.configuration,
            matchFormat: setup.matchFormat,
            firstServingTeam: firstServingTeam,
            proUnlocked: proUnlocked,
            demoPointCap: nil
        )
        let info = ActiveMatchInfo(
            match: match,
            startedAt: Date(),
            teamAName: setup.resolvedTeamAName,
            teamBName: setup.resolvedTeamBName,
            teamAPlayerIDs: setup.teamAPlayerIDs,
            teamBPlayerIDs: setup.teamBPlayerIDs
        )
        lifecycleState = .active(info)
        gameCompletionDates = []
        persistSnapshot()
        liveActivity.begin(attributes: liveActivityAttributes(for: info), state: .init(match: match))
    }

    func recordPoint(for team: Team) {
        match?.recordPoint(for: team)
        syncGameCompletionDates()
        persistSnapshot()
        pushLiveActivityUpdate()
    }

    func undo() {
        match?.undo()
        syncGameCompletionDates()
        persistSnapshot()
        pushLiveActivityUpdate()
    }

    func correctScores(teamA: Int, teamB: Int) {
        match?.correctScores(teamA: teamA, teamB: teamB)
        syncGameCompletionDates()
        persistSnapshot()
        pushLiveActivityUpdate()
    }

    @discardableResult
    func requestTimeout(for team: Team) -> Bool {
        guard let match else { return false }
        let started = match.requestTimeout(for: team)
        if started { persistSnapshot() }
        return started
    }

    @discardableResult
    func finishMatch() throws -> MatchRecord {
        guard case .active(let info) = lifecycleState else {
            throw ActiveMatchControllerError.noActiveMatch
        }
        let teamAPlayers = try repository.fetchSavedPlayers(ids: info.teamAPlayerIDs)
        let teamBPlayers = try repository.fetchSavedPlayers(ids: info.teamBPlayerIDs)
        let historyCountBeforeSave = currentHistoryCount()
        let record = try repository.saveCompletedMatch(
            info.match,
            teamAName: info.teamAName,
            teamBName: info.teamBName,
            startedAt: info.startedAt,
            teamAPlayers: teamAPlayers,
            teamBPlayers: teamBPlayers,
            gameCompletionDates: gameCompletionDates
        )
        recordCompletedMatchSaved(historyCountBeforeSave: historyCountBeforeSave)
        // Only after the save succeeded (it throws for a match that is not over,
        // so this is always a finished match): the final score lingers briefly,
        // since the system default would keep it on the Lock Screen for hours.
        liveActivity.end(
            finalState: .init(match: info.match),
            dismissal: .afterDelay(LiveActivityController.finishedDismissalDelay)
        )
        lifecycleState = .idle
        clearStoredActiveMatchDetails()
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
        clearStoredActiveMatchDetails()
        try? repository.clearInProgressSnapshot()
        liveActivity.end(finalState: nil, dismissal: .immediate)
    }

    /// Test-only: discards any live/resumed match or staged-but-unflipped
    /// setup, plus any persisted snapshot, so a UI test starts from a
    /// guaranteed-clean slate regardless of what a previous run or app
    /// session left behind.
    func clearAnyInProgressMatchForTesting() {
        lifecycleState = .idle
        liveActivity.end(finalState: nil, dismissal: .immediate)
        clearStoredActiveMatchDetails()
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
        // The lifetime counter is part of the demo budget, so a clean slate
        // must reset it too.
        userDefaults.removeObject(forKey: Keys.lifetimeCompletedMatchCount)
        try? repository.deleteAllMatchHistory()
        try? repository.deleteAllSavedPlayers()
    }

    /// Called from `recordPoint`/`undo`/`correctScores` only — each of
    /// those can move `completedGames.count` by at most one in either
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

    private func liveActivityAttributes(for info: ActiveMatchInfo) -> PickleballActivityAttributes {
        PickleballActivityAttributes(match: info.match, teamAName: info.teamAName, teamBName: info.teamBName)
    }

    /// Same trigger points as `persistSnapshot()`; the Live Activity controller
    /// skips the push when nothing it shows changed (e.g. a timeout).
    private func pushLiveActivityUpdate() {
        guard case .active(let info) = lifecycleState else { return }
        liveActivity.update(.init(match: info.match))
    }

    private func persistSnapshot() {
        guard case .active(let info) = lifecycleState else { return }
        try? repository.saveInProgressSnapshot(for: info.match, startedAt: info.startedAt)
    }
}

/// Which of a team's two partners started each game on the right, as explicit
/// per-game entries. Entries are kept even when the game number goes down (an
/// undo back into game N-1 must still find N-1's setting), and a game without
/// an entry inherits the nearest earlier game's, so a pair that stands in
/// swapped order keeps it across games.
struct StartingSideOverrides: Equatable {
    /// Game index (as a string, so the dictionary is a valid property list for
    /// UserDefaults) -> whether Player 2 starts on the right.
    private var teamA: [String: Bool]
    private var teamB: [String: Bool]

    init(teamA: [String: Bool] = [:], teamB: [String: Bool] = [:]) {
        self.teamA = teamA
        self.teamB = teamB
    }

    func isSwapped(for team: Team, gameIndex: Int) -> Bool {
        let entries = team == .teamA ? teamA : teamB
        let nearest = entries
            .compactMap { key, value in Int(key).map { ($0, value) } }
            .filter { $0.0 <= gameIndex }
            .max { $0.0 < $1.0 }
        return nearest?.1 ?? false
    }

    mutating func set(_ value: Bool, for team: Team, gameIndex: Int) {
        if team == .teamA {
            teamA[String(gameIndex)] = value
        } else {
            teamB[String(gameIndex)] = value
        }
    }

    func stored(for team: Team) -> [String: Bool] {
        team == .teamA ? teamA : teamB
    }
}
