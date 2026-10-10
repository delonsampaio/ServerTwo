import SwiftUI
import SwiftData
import PickleballKit

/// The app's default landing tab: a quick-glance summary (last match, total
/// matches played, and a Pro upsell or share shortcut) above a pinned "New
/// Match" button that switches `RootTabView` over to the Play tab.
///
/// Deliberately plain (no background imagery) — see Scoring screen's
/// explicit courtside-legibility priority, which doesn't apply here, but
/// this screen hasn't earned visual complexity yet either.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveMatchController.self) private var activeMatchController
    let onNewMatch: () -> Void

    @State private var matches: [MatchRecord] = []
    @State private var mePlayer: SavedPlayer?
    @State private var loadError: Error?
    @State private var isShowingPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    if let lastMatch = matches.first {
                        lastMatchCard(lastMatch)
                        matchesPlayedCard
                        thirdSlot(lastMatch: lastMatch)
                    } else if loadError != nil {
                        ContentUnavailableView(
                            "Couldn't Load History",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Pull down to try again, or just start a new match.")
                        )
                        .padding(.top, 40)
                    } else {
                        Text("Play your first match to see it here.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                    }
                }
                .padding()
            }
            .refreshable { loadMatches() }

            Divider()

            Button("New Match") {
                onNewMatch()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding()
            .accessibilityIdentifier("New Match")
        }
        .navigationTitle("Server Two")
        .task { loadMatches() }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
    }

    private func lastMatchCard(_ match: MatchRecord) -> some View {
        let teamAName = (match.teamSides ?? []).first { $0.team == .teamA }?.displayName ?? "Team A"
        let teamBName = (match.teamSides ?? []).first { $0.team == .teamB }?.displayName ?? "Team B"
        let games = (match.games ?? []).sorted { $0.gameNumber < $1.gameNumber }
        let teamAGames = games.filter { $0.winningTeam == .teamA }.count
        let teamBGames = games.filter { $0.winningTeam == .teamB }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("Last Match")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(teamAName) vs \(teamBName)")
                .font(.headline)
            Text("\(teamAGames) - \(teamBGames)")
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var matchesPlayedCard: some View {
        Group {
            if let mePlayer {
                let repository = MatchRepository(modelContext: modelContext)
                let record = repository.personalRecord(for: mePlayer, in: matches)
                HStack {
                    Text("Your Record")
                        .font(.subheadline)
                        .accessibilityIdentifier("Your Record")
                    Spacer()
                    Text("\(record.wins) - \(record.losses)")
                        .font(.headline)
                        .accessibilityIdentifier("YourRecordValue")
                }
            } else {
                HStack {
                    Text("Matches Played")
                        .font(.subheadline)
                    Spacer()
                    Text("\(matches.count)")
                        .font(.headline)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Pro upsell if locked (consistent with every other paywall trigger in
    /// the app); a share shortcut for the last match if unlocked, rather
    /// than leaving the slot empty or showing a "you already own this"
    /// banner nobody needs to see.
    @ViewBuilder
    private func thirdSlot(lastMatch: MatchRecord) -> some View {
        if activeMatchController.proUnlocked {
            HStack {
                Text("Share your last match")
                    .font(.subheadline)
                Spacer()
                MatchRecapShareButton(match: lastMatch)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else {
            Button {
                isShowingPaywall = true
            } label: {
                HStack {
                    Image(systemName: "lock.fill")
                    Text("Unlock Server Two Pro — $1.99")
                        .font(.subheadline.bold())
                    Spacer()
                }
            }
            .padding()
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("Home Unlock Pro Banner")
        }
    }

    private func loadMatches() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            matches = try repository.fetchMatchHistory()
            mePlayer = try repository.fetchMePlayer()
            loadError = nil
        } catch {
            matches = []
            loadError = error
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(onNewMatch: {})
    }
    .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
