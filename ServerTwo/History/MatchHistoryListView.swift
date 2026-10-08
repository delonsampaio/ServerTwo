import SwiftUI
import SwiftData
import PickleballKit

struct MatchHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var matches: [MatchRecord] = []

    var body: some View {
        List {
            if !matches.isEmpty {
                Section {
                    StatsSummaryView(matches: matches)
                }
            }
            Section("Matches") {
                if matches.isEmpty {
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
        return VStack(alignment: .leading) {
            Text("\(teamAName) vs \(teamBName)")
                .font(.headline)
            Text(match.completedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadMatches() {
        let repository = MatchRepository(modelContext: modelContext)
        matches = (try? repository.fetchMatchHistory()) ?? []
    }
}

#Preview {
    NavigationStack {
        MatchHistoryListView()
    }
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
