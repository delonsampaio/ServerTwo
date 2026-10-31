import SwiftUI
import PickleballKit

/// Shows the screen `WatchFlow` picks from the session's state (scoring, game
/// over and match over follow the engine, so a relaunch lands on the right
/// one); the only local state is the coin-flip step, owned by the tested flow.
struct WatchRootView: View {
    let session: StandaloneMatchSession
    let access: WatchAccess
    let workout: WorkoutController
    @State private var flow: WatchFlow
    @State private var rules = LastUsedRules()

    init(
        session: StandaloneMatchSession, access: WatchAccess, workout: WorkoutController,
        initialFlow: WatchFlow = WatchFlow()
    ) {
        self.session = session
        self.access = access
        self.workout = workout
        _flow = State(initialValue: initialFlow)
    }

    var body: some View {
        NavigationStack {
            switch flow.screen(
                isActive: session.isActive, isGameOver: session.isGameOver, isMatchOver: session.isMatchOver
            ) {
            case .matchOver:
                MatchOverView(session: session)
            case .gameOver:
                GameOverView(session: session)
            case .scoring:
                ScoringView(session: session, workout: workout)
            case .coinFlip:
                CoinFlipView(
                    onCancel: { flow.coinFlipCancelled() },
                    onBegin: { firstServer in
                        rules.save()
                        // Clear the coin-flip step BEFORE the match exists, so
                        // when "Done" later ends it the flow shows Home.
                        flow.matchBegan()
                        session.start(
                            configuration: rules.configuration,
                            format: rules.matchFormat,
                            firstServingTeam: firstServer
                        )
                    }
                )
            case .home:
                // The free-demo gate is checked here, when a match is about to
                // start, and never mid-match.
                HomeView(rules: $rules, access: access, onStart: {
                    guard access.canStartMatch else { return }
                    flow.startMatchTapped()
                })
            }
        }
        // StoreKit's cached entitlements: read at launch, free to repeat.
        .task { await access.refreshEntitlements() }
    }
}
