#if DEBUG
import Foundation
import PickleballKit

/// Debug-only launch arguments that put the app on a given screen with a
/// sample score, so each screen can be screenshotted in the simulator without
/// tapping through the flow:
///
///     -Debug-WatchDemoMatch                         doubles best of 3, game 2, Team A serving
///     -Debug-WatchDemoMatch -Debug-WatchDemoState <scoringB|gameOver|matchOver|sideSwitch|coinFlip>
struct WatchDemo {
    let state: String

    init?(arguments: [String]) {
        guard arguments.contains("-Debug-WatchDemoMatch") else { return nil }
        if let index = arguments.firstIndex(of: "-Debug-WatchDemoState"), arguments.indices.contains(index + 1) {
            state = arguments[index + 1]
        } else {
            state = "scoringA"
        }
    }

    @MainActor
    func apply(to session: StandaloneMatchSession) -> WatchFlow {
        var flow = WatchFlow()
        if state == "coinFlip" {
            flow.startMatchTapped()
            return flow
        }
        let bestOfThree = state != "sideSwitch"
        session.start(
            configuration: GameConfiguration(playMode: .doubles, scoringFormat: .sideOut),
            format: bestOfThree ? .bestOfThree : .bestOfOne,
            firstServingTeam: .teamA
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
        session.start(
            configuration: GameConfiguration(playMode: .singles, scoringFormat: .sideOut),
            format: .bestOfOne,
            firstServingTeam: .teamA
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
