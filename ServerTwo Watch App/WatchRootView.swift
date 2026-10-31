import SwiftUI
import PickleballKit

/// Picks the screen from the session: scoring, game over and match over follow
/// the engine's state (so a relaunch lands on the right one); only the two
/// pre-match screens (home, coin flip) are local state.
struct WatchRootView: View {
    enum Stage { case home, coinFlip }

    let session: StandaloneMatchSession
    @State private var stage: Stage
    @State private var rules = LastUsedRules()

    init(session: StandaloneMatchSession, initialStage: Stage = .home) {
        self.session = session
        _stage = State(initialValue: initialStage)
    }

    var body: some View {
        NavigationStack {
            if session.isActive {
                if session.isMatchOver {
                    MatchOverView(session: session)
                } else if session.isGameOver {
                    GameOverView(session: session)
                } else {
                    ScoringView(session: session, onAbandon: { stage = .home })
                }
            } else if stage == .coinFlip {
                CoinFlipView(
                    onCancel: { stage = .home },
                    onBegin: { firstServer in
                        rules.save()
                        session.start(
                            configuration: rules.configuration,
                            format: rules.matchFormat,
                            firstServingTeam: firstServer
                        )
                    }
                )
            } else {
                HomeView(rules: $rules, onStart: { stage = .coinFlip })
            }
        }
    }
}
