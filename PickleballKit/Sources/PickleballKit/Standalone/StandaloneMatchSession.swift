import Foundation
import Observation

/// One standalone match on one device, end to end: the engine, the local
/// crash-recovery snapshot, saving the finished match and queueing it for the
/// iPhone. Platform-neutral so the Watch app's views stay thin and every rule
/// here is covered by `swift test` instead of by tapping a simulator.
///
/// Mirrors what the iOS `ActiveMatchController` does around `PickleballMatch`
/// (snapshot after every mutation, live game completion dates) without the
/// phone-only parts (saved players, Live Activity, demo gate, correction).
/// A match in progress never leaves the device; only the finished match is
/// saved (and marked pending for the phone).
@MainActor
@Observable
public final class StandaloneMatchSession {
    public static let teamAName = "Team A"
    public static let teamBName = "Team B"

    /// What a tap did, so the UI can pick the haptic without re-deriving it.
    public enum PointOutcome: Equatable, Sendable {
        /// Nothing changed: no match, the match is over, a Game Over or
        /// side-switch notice is up, or the game just ended.
        case ignored
        case point
        /// Doubles side-out: Server 1 lost the rally, Server 2 is up.
        case secondServer
        /// The serve passed to the other team without a point.
        case sideOut
        case gameOver
        case matchOver
    }

    public struct GameSummary: Equatable, Sendable {
        public let gameNumber: Int
        public let winner: Team
        public let teamAScore: Int
        public let teamBScore: Int
        /// Who serves the next game (Rule 21.F.2: the team that did NOT serve
        /// first in this game); `nil` when this game decided the match.
        public let nextServingTeam: Team?

        public var winnerScore: Int { max(teamAScore, teamBScore) }
        public var loserScore: Int { min(teamAScore, teamBScore) }
    }

    public private(set) var match: PickleballMatch?
    /// A game just ended and the match goes on: the Game Over screen is up and
    /// scoring is held until `startNextGame()`. Deliberately false once the
    /// match itself is decided (`isMatchOver`).
    public private(set) var isGameOver = false
    /// Non-nil while the "Switch sides" notice is up; scoring is held until
    /// `acknowledgeSideSwitchNotice()` so a tap meant to dismiss it can't score.
    public private(set) var sideSwitchNotice: SideSwitchDirection?

    private let repository: MatchRepository
    private let pendingSync: PendingSyncStore
    /// Matches this Watch has completed for life (the free-demo budget):
    /// +1 when a finished match is saved, -1 when its deciding point is undone.
    private let lifetimeCounter: WatchLifetimeCounter
    private let now: () -> Date

    private var startedAt = Date()
    /// Positional with `match.completedGames`; `nil` for games finished before
    /// a relaunch (their wall-clock time was not captured by this session).
    private var gameCompletionDates: [Date?] = []
    private var sideSwitchTracker = SideSwitchPromptTracker()
    private var savedRecord: MatchRecord?
    /// A saved record whose deletion failed when the deciding point was undone.
    /// Kept (and kept in the pending queue) until a delete succeeds, which is
    /// retried at the next save, so a failure can never leave an orphan plus a
    /// second record for the same match.
    private var staleRecord: MatchRecord?

    /// Called after "Done" has saved the match and returned to idle. The sync
    /// coordinator hooks in here: Done is the moment the finished match can no
    /// longer be undone, so it is the moment it may be sent to the iPhone.
    public var onFinishedMatchDismissed: (@MainActor () -> Void)?

    /// The id of the finished match that is still on the match-over screen,
    /// where Undo can delete it. It must not be sent to the iPhone yet, or an
    /// undo after the send would leave the phone with a match that never
    /// finished (and the replayed one as a second match).
    public var undoableSavedMatchID: UUID? { savedRecord?.id }

    /// Every match id sync must leave alone for now: the undoable one, and a
    /// record whose delete failed after an undo (it is not a real match, and
    /// is deleted at the next save).
    public var heldBackMatchIDs: Set<UUID> {
        Set([savedRecord?.id, staleRecord?.id].compactMap { $0 })
    }

    /// Test seams. `deleteMatchRecord` defaults to the repository's delete;
    /// `saveFailureForTesting` makes the next save(s) throw.
    var deleteMatchRecord: (MatchRecord) throws -> Void
    var saveFailureForTesting: Error?
    /// Runs right before the repository save, after the id was queued.
    var beforeSaveForTesting: (() -> Void)?

    public init(
        repository: MatchRepository,
        pendingSync: PendingSyncStore = PendingSyncStore(),
        lifetimeCounter: WatchLifetimeCounter = WatchLifetimeCounter(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.pendingSync = pendingSync
        self.lifetimeCounter = lifetimeCounter
        self.now = now
        self.deleteMatchRecord = { try repository.deleteMatch($0) }
    }

    // MARK: Derived state for the UI

    public var isActive: Bool { match != nil }
    public var isMatchOver: Bool { match?.isMatchOver ?? false }
    public var matchWinner: Team? { match?.matchWinner }
    public var canUndo: Bool {
        guard let match else { return false }
        return match.currentGame.canUndo || !match.completedGames.isEmpty
    }

    public var configuration: GameConfiguration? { match?.configuration }
    public var matchFormat: MatchFormat? { match?.matchFormat }

    public var servingTeam: Team { match?.currentGame.state.servingTeam ?? .teamA }
    public var serverNumber: ServerNumber { match?.currentGame.state.serverNumber ?? .one }

    public func score(for team: Team) -> Int {
        match?.currentGame.state.score(for: team) ?? 0
    }

    public func gamesWon(for team: Team) -> Int {
        match?.gamesWon(for: team) ?? 0
    }

    public func teamName(for team: Team) -> String {
        team == .teamA ? Self.teamAName : Self.teamBName
    }

    /// Zero-based index of the game being played (the decided one once the
    /// match is over).
    public var currentGameIndex: Int {
        guard let match else { return 0 }
        return match.currentGameIsCounted ? max(0, match.completedGames.count - 1) : match.completedGames.count
    }

    public var lastCompletedGame: GameSummary? {
        guard let match, let game = match.completedGames.last else { return nil }
        // `gameWinner` is nil only for a legacy snapshot decided at a score the
        // strict rule no longer recognises; fall back to the higher score, as
        // `saveCompletedMatch` does.
        let winner = game.gameWinner
            ?? (game.state.teamAScore > game.state.teamBScore ? Team.teamA : Team.teamB)
        return GameSummary(
            gameNumber: match.completedGames.count,
            winner: winner,
            teamAScore: game.state.teamAScore,
            teamBScore: game.state.teamBScore,
            nextServingTeam: match.isMatchOver ? nil : game.initialServingTeam.opponent
        )
    }

    /// Final scores of every finished game, for the match-over screen.
    public var completedGameScores: [(teamA: Int, teamB: Int)] {
        (match?.completedGames ?? []).map { ($0.state.teamAScore, $0.state.teamBScore) }
    }

    /// The serving badge: "SERVER 1/2" only in doubles side-out (the one format
    /// with a server number worth showing), plain "SERVING" otherwise, `nil`
    /// for the receiving team or once the match is decided. Same wording as the
    /// iPhone's `ServingBadge`.
    public func servingCaption(for team: Team) -> String? {
        guard let match, !match.isMatchOver, team == servingTeam else { return nil }
        guard match.configuration.scoringFormat == .sideOut, match.configuration.playMode == .doubles else {
            return "SERVING"
        }
        return "SERVER \(serverNumber.rawValue)"
    }

    /// What a tap on this team's zone means, same wording as the iPhone's score
    /// card caption: in side-out scoring a tap on the receiving team is not a
    /// point but "second server" or "side out", which users otherwise tapped
    /// twice by mistake.
    public func tapCaption(for team: Team) -> String {
        guard let match, match.configuration.scoringFormat == .sideOut, team != servingTeam else {
            return "Tap to Score"
        }
        // Doubles Server 1 losing a rally hands the serve to Server 2 (same
        // team); anything else (singles, or Server 2) is a full side out.
        return match.configuration.playMode == .doubles && serverNumber == .one
            ? "Tap for 2nd Server" : "Tap for Side Out"
    }

    /// The VoiceOver label for a team's tap zone, e.g.
    /// "Team A, 7 points, serving, server 2".
    public func spokenSummary(for team: Team) -> String {
        let points = score(for: team)
        var parts = ["\(teamName(for: team)), \(points) \(points == 1 ? "point" : "points")"]
        if servingCaption(for: team) != nil {
            parts.append("serving")
            if let match, match.configuration.scoringFormat == .sideOut, match.configuration.playMode == .doubles {
                parts.append("server \(serverNumber.rawValue)")
            }
        }
        // Games won only where the format has games, mirroring the visible
        // "Games N" line.
        if let match, match.matchFormat != .bestOfOne {
            let won = gamesWon(for: team)
            parts.append(won == 0 ? "no games won" : "\(won) \(won == 1 ? "game" : "games") won")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Lifecycle

    /// Begins a fresh match (replacing any saved snapshot) once the coin flip
    /// has decided who serves first.
    public func start(configuration: GameConfiguration, format: MatchFormat, firstServingTeam: Team) {
        let newMatch = PickleballMatch(
            configuration: configuration,
            matchFormat: format,
            firstServingTeam: firstServingTeam,
            // The demo gate is a match-start decision handled elsewhere; a
            // started match is never capped mid-game.
            proUnlocked: true,
            demoPointCap: nil
        )
        match = newMatch
        startedAt = now()
        gameCompletionDates = []
        isGameOver = false
        sideSwitchNotice = nil
        savedRecord = nil
        sideSwitchTracker = SideSwitchPromptTracker()
        sideSwitchTracker.seed(completedGameFlags: [], currentGameFlag: false)
        persistSnapshot()
    }

    /// Restores a match interrupted by a relaunch or crash. Returns whether
    /// there was one. Teams are always the default names on the Watch, so only
    /// the engine state and the start time need restoring.
    @discardableResult
    public func resumeIfNeeded() -> Bool {
        guard match == nil,
              let resumed = try? repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil)
        else { return match != nil }
        let restored = resumed.match
        match = restored
        startedAt = resumed.startedAt
        gameCompletionDates = Array(repeating: nil, count: restored.completedGames.count)
        savedRecord = nil
        sideSwitchNotice = nil
        // A fresh game right after finished ones means the players were looking
        // at the Game Over screen (or just tapped Next Game): showing it again
        // is harmless and loses nothing.
        isGameOver = !restored.completedGames.isEmpty && !restored.currentGame.canUndo
        sideSwitchTracker = SideSwitchPromptTracker()
        sideSwitchTracker.seed(
            completedGameFlags: restored.completedGames.map(\.state.hasSideSwitched),
            currentGameFlag: restored.currentGame.state.hasSideSwitched
        )
        return true
    }

    /// `afterUpdate` runs once the visible state has changed and BEFORE the
    /// slower snapshot write (JSON encode, fetch, delete, insert, save), so the
    /// caller can fire the haptic without waiting for the disk.
    @discardableResult
    public func recordPoint(for team: Team, afterUpdate: (PointOutcome) -> Void = { _ in }) -> PointOutcome {
        guard let match, !match.isMatchOver, !isGameOver, sideSwitchNotice == nil else { return .ignored }
        let before = match.currentGame.state
        let gamesBefore = match.completedGames.count

        match.recordPoint(for: team)
        syncGameCompletionDates()

        let outcome: PointOutcome
        if match.isMatchOver {
            outcome = .matchOver
        } else if match.completedGames.count > gamesBefore {
            isGameOver = true
            outcome = .gameOver
        } else {
            let after = match.currentGame.state
            if after.teamAScore != before.teamAScore || after.teamBScore != before.teamBScore {
                outcome = .point
            } else if after.servingTeam != before.servingTeam {
                outcome = .sideOut
            } else {
                outcome = .secondServer
            }
        }

        updateSideSwitchNotice()
        afterUpdate(outcome)
        if match.isMatchOver {
            // Saved the moment it ends, not on "Done": the Watch app can be
            // suspended or killed on the match-over screen, and a snapshot of a
            // decided match is discarded on relaunch anyway, so none is written
            // for it. If this save fails the previous snapshot (one point
            // short) is still there to resume from, and Done retries the save.
            _ = try? saveIfNeeded()
        } else {
            persistSnapshot()
        }
        return outcome
    }

    public func undo() {
        guard let match, canUndo else { return }
        let hadNotice = sideSwitchNotice != nil
        sideSwitchNotice = nil
        isGameOver = false
        if savedRecord != nil { unsaveFinishedMatch() }

        match.undo()
        syncGameCompletionDates()

        if hadNotice {
            // The players never got to act on the pending notice, so what they
            // were last told is simply the court as it is now.
            sideSwitchTracker.resync(gameIndex: currentGameIndex, to: match.currentGame.state.hasSideSwitched)
        } else {
            updateSideSwitchNotice()
        }
        persistSnapshot()
    }

    /// Leaves the Game Over screen for the next game (already created by the
    /// engine with the alternated first server).
    public func startNextGame() {
        isGameOver = false
        updateSideSwitchNotice()
    }

    public func acknowledgeSideSwitchNotice() {
        sideSwitchNotice = nil
    }

    // MARK: Finishing

    /// Saves the finished match to the local store (once) and queues it for the
    /// iPhone. Idempotent: the match is normally already saved when it ended, so
    /// this returns that record; it only saves if that automatic save failed.
    @discardableResult
    public func finish() throws -> MatchRecord {
        try saveIfNeeded()
    }

    /// The match-over screen's "Done": make sure the match is saved, then
    /// return to idle.
    public func dismissFinishedMatch() throws {
        _ = try saveIfNeeded()
        reset()
        onFinishedMatchDismissed?()
    }

    /// Abandons without saving anything and drops the snapshot.
    public func abandon() {
        // A match that is already saved (and pending) is finished, not
        // abandoned: dropping the session state here would leave its record
        // queued with nobody to send it until the next launch. The screens
        // never offer this (End Match is on the scoring screen only), so this
        // makes the unreachable case safe instead of silent.
        if savedRecord != nil {
            reset()
            onFinishedMatchDismissed?()
            return
        }
        try? repository.clearInProgressSnapshot()
        removeStaleRecord()
        reset()
    }

    // MARK: Private

    private func reset() {
        match = nil
        isGameOver = false
        sideSwitchNotice = nil
        gameCompletionDates = []
        savedRecord = nil
    }

    private func saveIfNeeded() throws -> MatchRecord {
        if let savedRecord { return savedRecord }
        guard let match else { throw MatchRepositoryError.matchNotOver }
        // Replace, never duplicate: a record whose delete failed earlier goes
        // first; if it still cannot be deleted the save fails (Done retries).
        if let stale = staleRecord {
            try deleteMatchRecord(stale)
            pendingSync.confirmSynced(stale.id)
            staleRecord = nil
        }
        // Queued BEFORE the save, with the id the record will get: a crash
        // between the two leaves a pending id with no record (sync drops it),
        // whereas the other order could leave a saved match nobody sends.
        let id = UUID()
        pendingSync.markPending(id)
        let record: MatchRecord
        do {
            beforeSaveForTesting?()
            if let saveFailureForTesting { throw saveFailureForTesting }
            record = try repository.saveCompletedMatch(
                match,
                teamAName: Self.teamAName,
                teamBName: Self.teamBName,
                startedAt: startedAt,
                completedAt: now(),
                gameCompletionDates: gameCompletionDates,
                id: id
            )
        } catch {
            // The save can fail AFTER the record was stored (clearing the
            // snapshot is its last step). Then the match exists: keep it queued
            // and use it, or a retry would save the same match a second time.
            guard let stored = try? repository.fetchMatchRecord(id: id) else {
                pendingSync.confirmSynced(id)
                throw error
            }
            savedRecord = stored
            lifetimeCounter.increment()
            return stored
        }
        savedRecord = record
        lifetimeCounter.increment()
        return record
    }

    /// Undoing the match-deciding point reopens the match, so the record saved
    /// when it ended must go (and leave the pending queue) or the same match
    /// would later be saved again with its real result.
    private func unsaveFinishedMatch() {
        guard let record = savedRecord else { return }
        savedRecord = nil
        // The match is open again, so it no longer counts toward the demo (the
        // replayed ending counts when it is saved); decided here, not on the
        // delete result, or a failed delete would count the match twice.
        lifetimeCounter.decrement()
        do {
            try deleteMatchRecord(record)
            pendingSync.confirmSynced(record.id)
        } catch {
            // Keep it (and its pending id) for the retry at the next save.
            staleRecord = record
        }
    }

    /// Best effort when abandoning: a leftover stale record is removed if the
    /// store lets us; otherwise it stays queued rather than being forgotten.
    private func removeStaleRecord() {
        guard let stale = staleRecord else { return }
        if (try? deleteMatchRecord(stale)) != nil {
            pendingSync.confirmSynced(stale.id)
            staleRecord = nil
        }
    }

    private func updateSideSwitchNotice() {
        guard let match, !match.isMatchOver, !isGameOver else { return }
        let gameIndex = currentGameIndex
        // The mid-game end change applies only in the last game of the format
        // (Rule 21.B); between games teams always change ends (Rule 21.F.2),
        // which the Game Over screen says.
        guard match.matchFormat.isLastGame(index: gameIndex) else { return }
        if let direction = sideSwitchTracker.next(
            gameIndex: gameIndex, hasSwitched: match.currentGame.state.hasSideSwitched
        ) {
            sideSwitchNotice = direction
        }
    }

    /// Same grow-by-one/shrink-by-one rule as the iOS controller: every
    /// mutation moves the completed-game count by at most one.
    private func syncGameCompletionDates() {
        guard let count = match?.completedGames.count else { return }
        if gameCompletionDates.count > count {
            gameCompletionDates.removeLast(gameCompletionDates.count - count)
        } else if gameCompletionDates.count < count {
            gameCompletionDates.append(contentsOf: Array(repeating: now(), count: count - gameCompletionDates.count))
        }
    }

    private func persistSnapshot() {
        guard let match else { return }
        try? repository.saveInProgressSnapshot(for: match, startedAt: startedAt)
    }
}
