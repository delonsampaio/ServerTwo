import SwiftUI
import SwiftData
import PickleballKit

struct MatchHistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    let onRematch: (RematchRequest) -> Void
    @State private var matches: [MatchRecord] = []
    @State private var mePlayer: SavedPlayer?
    @State private var loadError: Error?
    @State private var filterPlayerID: UUID?

    /// Every `SavedPlayer` who actually appears in this history, not the
    /// full roster — offering a filter that's guaranteed to show zero
    /// matches (someone saved but never played) would be a dead end.
    private var availableFilterPlayers: [SavedPlayer] {
        var seenIDs: Set<UUID> = []
        var players: [SavedPlayer] = []
        for match in matches {
            for side in match.teamSides ?? [] {
                for player in side.players ?? [] {
                    if seenIDs.insert(player.id).inserted {
                        players.append(player)
                    }
                }
            }
        }
        return players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filterPlayerName: String? {
        guard let filterPlayerID else { return nil }
        return availableFilterPlayers.first { $0.id == filterPlayerID }?.name
    }

    /// Matches a selected player appears in, on either team. Feeding this
    /// (rather than the unfiltered `matches`) into `StatsSummaryView` below
    /// turns "Your Record" into a head-to-head record against whoever's
    /// selected, for free — it already computes purely from whatever match
    /// array it's handed.
    private var filteredMatches: [MatchRecord] {
        guard let filterPlayerID else { return matches }
        return matches.filter { match in
            (match.teamSides ?? []).contains { side in
                (side.players ?? []).contains { $0.id == filterPlayerID }
            }
        }
    }

    var body: some View {
        List {
            if !matches.isEmpty {
                Section {
                    StatsSummaryView(matches: filteredMatches, mePlayer: mePlayer, repository: MatchRepository(modelContext: modelContext))
                }
            }
            Section(filterPlayerName.map { "Matches · \($0)" } ?? "Matches") {
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
                } else if filteredMatches.isEmpty {
                    ContentUnavailableView(
                        "No Matches Found",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No matches with \(filterPlayerName ?? "this player") yet.")
                    )
                } else {
                    ForEach(filteredMatches) { match in
                        NavigationLink(value: match) {
                            matchRow(match)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !availableFilterPlayers.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
        }
        .navigationDestination(for: MatchRecord.self) { match in
            MatchDetailView(match: match, onRematch: onRematch)
        }
        .task { loadMatches() }
        .refreshable { loadMatches() }
    }

    private var filterMenu: some View {
        Menu {
            Button {
                filterPlayerID = nil
            } label: {
                if filterPlayerID == nil {
                    Label("All Matches", systemImage: "checkmark")
                } else {
                    Text("All Matches")
                }
            }
            Divider()
            ForEach(availableFilterPlayers, id: \.id) { player in
                Button {
                    filterPlayerID = player.id
                } label: {
                    if filterPlayerID == player.id {
                        Label(player.name, systemImage: "checkmark")
                    } else {
                        Text(player.name)
                    }
                }
            }
        } label: {
            Image(systemName: filterPlayerID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("History Filter Menu")
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
        MatchHistoryListView(onRematch: { _ in })
    }
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
