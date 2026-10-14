import SwiftUI
import PickleballKit

enum AppTab: Hashable {
    case home, play, history, settings
}

struct RootTabView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    @State private var selectedTab: AppTab
    @State private var pendingRematch: RematchRequest?
    @State private var pendingQuickStart: QuickStartRequest?

    /// `initialTab` is computed once by `MyApp` (which already holds
    /// `ActiveMatchController` directly, not via `@Environment`) and passed
    /// in, rather than defaulting to `.home` here and correcting via
    /// `.onAppear` — that would flash Home for one frame before jumping to
    /// Play on a crash-recovery relaunch, which Phase 3 specifically
    /// guaranteed never happens.
    init(initialTab: AppTab) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(onNewMatch: { selectedTab = .play }, onRematch: startRematch, onQuickStart: startQuickStart)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                playTabContent
            }
            .tabItem { Label("Play", systemImage: "figure.pickleball") }
            .tag(AppTab.play)

            NavigationStack {
                MatchHistoryListView(onRematch: startRematch)
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(AppTab.history)

            NavigationStack {
                // Both ManagePlayersView's player rows and
                // PlayerDetailView's match rows (two and three pushes
                // deep in this stack) use plain destination-based
                // `NavigationLink`s, constructing their destination
                // directly, rather than `NavigationLink(value:)` +
                // `.navigationDestination(for:)` — that style, even
                // registered at this stack's root, silently did nothing
                // on tap once the tapped row was itself inside content
                // reached via an older destination-based push. Confirmed
                // with an actual assertion after the tap, not just a
                // screenshot that happened to be taken before noticing
                // nothing had changed.
                SettingsView(onRematch: startRematch)
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(AppTab.settings)
        }
    }

    @ViewBuilder
    private var playTabContent: some View {
        if activeMatchController.match != nil {
            ScoringView()
        } else if let setup = activeMatchController.pendingMatchSetup {
            // "Start Match" was tapped, but who serves first isn't decided
            // yet — `PickleballMatch` can't be created without that.
            CoinFlipView(setup: setup)
        } else {
            MatchSetupView(
                pendingRematch: pendingRematch,
                onPrefillConsumed: { pendingRematch = nil },
                pendingQuickStart: pendingQuickStart,
                onQuickStartConsumed: { pendingQuickStart = nil }
            )
        }
    }

    private func startRematch(_ request: RematchRequest) {
        pendingRematch = request
        selectedTab = .play
    }

    private func startQuickStart(_ request: QuickStartRequest) {
        pendingQuickStart = request
        selectedTab = .play
    }
}
