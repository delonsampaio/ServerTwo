import SwiftUI
import SwiftData
import PickleballKit

struct MatchHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var matches: [MatchRecord] = []
    @State private var mePlayer: SavedPlayer?
    @State private var loadError: Error?

    var body: some View {
        List {
            if !matches.isEmpty {
                Section {
                    StatsSummaryView(matches: matches, mePlayer: mePlayer, repository: MatchRepository(modelContext: modelContext))
                }
            }
            Section("Matches") {
                if matches.isEmpty, loadError != nil {
                    // A swallowed fetch failure used to masquerade as a genuine
                    // empty state, which reads as "your history was deleted."
                    ContentUnavailableView(
                        "Couldn't Load History",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Pull down to try again.")
                    )
                } else if matches.isEmpty {
                    ContentUnavailableView("No Matches Yet", systemImage: "sportscourt")
                } else {
                    ForEach(matches) { match in
                        NavigationLink(value: match) {
                            matchRow(match)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: MatchRecord.self) { match in
            MatchDetailView(match: match)
        }
        .task { loadMatches() }
        .refreshable { loadMatches() }
    }

    private func matchRow(_ match: MatchRecord) -> some View {
        let teamAName = (match.teamSides ?? []).first { $0.team == .teamA }?.displayName ?? "Team A"
        let teamBName = (match.teamSides ?? []).first { $0.team == .teamB }?.displayName ?? "Team B"
        let games = (match.games ?? []).sorted { $0.gameNumber < $1.gameNumber }
        let teamAGames = games.filter { $0.winningTeam == .teamA }.count
        let teamBGames = games.filter { $0.winningTeam == .teamB }.count
        return VStack(alignment: .leading) {
            Text("\(teamAName) vs \(teamBName)")
                .font(.headline)
                .accessibilityIdentifier("\(teamAName) vs \(teamBName)")
            Text("\(teamAGames) - \(teamBGames)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(match.completedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        MatchHistoryListView()
    }
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
