#if DEBUG
import Foundation
import PickleballKit

/// Debug-only launch arguments that put the app on a given screen with a
/// sample score, so each screen can be screenshotted in the simulator without
/// tapping through the flow:
///
///     -Debug-WatchDemoMatch                         doubles best of 3, game 2, Team A serving
///     -Debug-WatchDemoMatch -Debug-WatchDemoState <scoringB|gameOver|matchOver|sideSwitch|coinFlip|home|homeBlocked>
///     ... -Debug-WatchDemoPlayers                   also a saved-player list and a chosen doubles selection
struct WatchDemo {
    let state: String
    let withPlayers: Bool

    init?(arguments: [String]) {
        guard arguments.contains("-Debug-WatchDemoMatch") else { return nil }
        withPlayers = arguments.contains("-Debug-WatchDemoPlayers")
        if let index = arguments.firstIndex(of: "-Debug-WatchDemoState"), arguments.indices.contains(index + 1) {
            state = arguments[index + 1]
        } else {
            state = "scoringA"
        }
    }

    /// The demo's gate: `homeBlocked` shows Home with the free demo used (the
    /// phone reports one completed match, no Pro); every other state is open.
    /// Never touches StoreKit or the real counters.
    @MainActor
    func makeAccess(suiteName: String) -> WatchAccess {
        let counter = WatchLifetimeCounter(suiteName: suiteName)
        let access = WatchAccess(
            counter: counter, cache: WatchEntitlementCache(suiteName: suiteName), entitlements: NoWatchEntitlements()
        )
        access.apply(PhoneStateContext(proUnlocked: false, completedMatchCount: state == "homeBlocked" ? 1 : 0))
        return access
    }

    private static let demoList = [
        WatchPlayer(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Delon", isMe: true),
        WatchPlayer(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Mike"),
        WatchPlayer(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Sarah"),
        WatchPlayer(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Priya"),
        WatchPlayer(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Tom"),
    ]

    /// Delon and Sarah against Priya and Tom, all from `demoList`.
    private static var demoSelection: WatchPlayerSelection {
        func entry(_ index: Int) -> SyncedPlayerRef {
            SyncedPlayerRef(savedPlayerID: demoList[index].id, name: demoList[index].name)
        }
        return WatchPlayerSelection(teamA: [entry(0), entry(2)], teamB: [entry(3), entry(4)])
    }

    /// With `-Debug-WatchDemoPlayers`: a few saved players and a selection, in
    /// the demo defaults suite (never the real cache). Otherwise nothing.
    @MainActor
    func seedPlayers(directory: WatchPlayerDirectory, suiteName: String) -> LastUsedPlayers {
        guard withPlayers, let defaults = UserDefaults(suiteName: suiteName) else { return LastUsedPlayers() }
        directory.apply(PhoneStateContext(proUnlocked: false, completedMatchCount: 0, players: Self.demoList))
        var last = LastUsedPlayers(userDefaults: defaults)
        last.selection = Self.demoSelection
        return last
    }

    @MainActor
    func apply(to session: StandaloneMatchSession) -> WatchFlow {
        var flow = WatchFlow()
        if state == "homeBlocked" || state == "home" { return flow }
        if state == "coinFlip" {
            flow.startMatchTapped()
            return flow
        }
        let bestOfThree = state != "sideSwitch"
        session.start(
            configuration: GameConfiguration(playMode: .doubles, scoringFormat: .sideOut),
            format: bestOfThree ? .bestOfThree : .bestOfOne,
            firstServingTeam: .teamA,
            players: withPlayers ? Self.demoSelection.matchPlayers(for: .doubles) : .empty
        )
        switch state {
        case "gameOver":
            play(session, toScoreA: 11, b: 3)
        case "sideSwitch":
            // One point short of the threshold, then the point that crosses it,
            // so the notice is still up when the screenshot is taken.
            play(session, toScoreA: 5, b: 2)
            serve(session, .teamA)
            session.recordPoint(for: .teamA)
        case "scoringB":
            play(session, toScoreA: 11, b: 4)
            session.startNextGame()
            play(session, toScoreA: 3, b: 7)
            serve(session, .teamB)
        case "matchOver":
            play(session, toScoreA: 11, b: 4)
            session.startNextGame()
            play(session, toScoreA: 11, b: 9)
        default:
            play(session, toScoreA: 11, b: 4)
            session.startNextGame()
            play(session, toScoreA: 7, b: 3)
            serve(session, .teamA)
        }
        return flow
    }

    /// Taps until the board reads `a`-`b` (or the game/match ends first). In
    /// side-out play only the serving team scores, so once the server has hit
    /// its target the other team's taps hand the serve over.
    @MainActor
    private func play(_ session: StandaloneMatchSession, toScoreA a: Int, b: Int) {
        var taps = 0
        while taps < 400, !session.isGameOver, !session.isMatchOver,
              session.score(for: .teamA) != a || session.score(for: .teamB) != b {
            session.acknowledgeSideSwitchNotice()
            let serving = session.servingTeam
            let target = serving == .teamA ? a : b
            session.recordPoint(for: session.score(for: serving) < target ? serving : serving.opponent)
            taps += 1
        }
    }

    @MainActor
    private func serve(_ session: StandaloneMatchSession, _ team: Team) {
        var taps = 0
        while session.servingTeam != team, taps < 4 {
            session.recordPoint(for: team)
            taps += 1
        }
    }
}

/// Debug-only `-Debug-WatchAutoSyncMatch`: plays one quick match (singles, one
/// game to 11, Team A winning) against the REAL store and pending queue, then
/// taps Done, so the Watch to iPhone sync can be checked end to end on paired
/// simulators without a simulator being able to tap the watch screens.
enum WatchAutoSync {
    @MainActor
    static func playAndFinishIfRequested(on session: StandaloneMatchSession, arguments: [String]) {
        guard arguments.contains("-Debug-WatchAutoSyncMatch"), !session.isActive else { return }
        // `-Debug-WatchAutoSyncPlayers` adds two typed names (no saved player
        // ids), so the phone's import creates and links them.
        let players = arguments.contains("-Debug-WatchAutoSyncPlayers")
            ? WatchMatchPlayers(teamA: [SyncedPlayerRef(name: "Alex")], teamB: [SyncedPlayerRef(name: "Sam")])
            : .empty
        session.start(
            configuration: GameConfiguration(playMode: .singles, scoringFormat: .sideOut),
            format: .bestOfOne,
            firstServingTeam: .teamA,
            players: players
        )
        var taps = 0
        while !session.isMatchOver, taps < 100 {
            session.acknowledgeSideSwitchNotice()
            session.recordPoint(for: .teamA)
            taps += 1
        }
        try? session.dismissFinishedMatch()
    }
}
#endif
