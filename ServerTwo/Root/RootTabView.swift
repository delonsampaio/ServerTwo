import SwiftUI

enum AppTab: Hashable {
    case home, play, history, settings
}

struct RootTabView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    @State private var selectedTab: AppTab

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
                HomeView(onNewMatch: { selectedTab = .play })
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                playTabContent
            }
            .tabItem { Label("Play", systemImage: "figure.pickleball") }
            .tag(AppTab.play)

            NavigationStack {
                MatchHistoryListView()
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(AppTab.history)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(AppTab.settings)
        }
    }

    @ViewBuilder
    private var playTabContent: some View {
        if activeMatchController.match != nil {
            ScoringView()
        } else {
            MatchSetupView()
        }
    }
}
