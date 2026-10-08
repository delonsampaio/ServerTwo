import SwiftUI

struct RootTabView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController

    var body: some View {
        TabView {
            NavigationStack {
                playTabContent
            }
            .tabItem { Label("Play", systemImage: "figure.pickleball") }

            NavigationStack {
                MatchHistoryListView()
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
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
