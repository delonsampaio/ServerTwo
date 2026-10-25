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
    @State private var pendingDeletion: PendingMatchDeletion?
    // Bumped after Edit Players saved; see `refreshAfterPlayersEdited`.
    @State private var editRevision = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // 22 pt and 54 pt at the default text size; they scale with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var resultBadgeSize: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var scoreColumnWidth: CGFloat = 54

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
                        .id(editRevision)
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
                                .id(editRevision)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Not `role: .destructive`: that role collapses the
                            // row as if it were already deleted, and it did not
                            // come back when the alert was cancelled. The red is
                            // the system red.
                            Button {
                                pendingDeletion = PendingMatchDeletion(match: match)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                            .accessibilityIdentifier("Delete.\(rowIdentifier(match))")
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
        .refreshAfterPlayersEdited(revision: $editRevision) { loadMatches() }
        .refreshable { loadMatches() }
        .deleteMatchAlert(pending: $pendingDeletion) { loadMatches() }
    }

    /// The row title's identifier, "<A> vs <B>".
    private func rowIdentifier(_ match: MatchRecord) -> String {
        let sides = match.teamSides ?? []
        let teamA = sides.first { $0.team == .teamA }?.displayName ?? "Team A"
        let teamB = sides.first { $0.team == .teamB }?.displayName ?? "Team B"
        return "\(teamA) vs \(teamB)"
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
        .accessibilityLabel("Filter matches")
        .accessibilityValue(filterPlayerName ?? "All matches")
    }

    private func matchRow(_ match: MatchRecord) -> some View {
        let teamAName = (match.teamSides ?? []).first { $0.team == .teamA }?.displayName ?? "Team A"
        let teamBName = (match.teamSides ?? []).first { $0.team == .teamB }?.displayName ?? "Team B"
        let games = (match.games ?? []).sorted { $0.gameNumber < $1.gameNumber }
        let teamAGames = games.filter { $0.winningTeam == .teamA }.count
        let teamBGames = games.filter { $0.winningTeam == .teamB }.count
        // Whether `mePlayer` won this specific match (nil if they're unset
        // or didn't play in it) — lets the row show an at-a-glance W/L
        // badge instead of making the reader work out who's who from
        // which side of "vs" their own name happens to land on. Also
        // covers matches saved before a side's players were linked, via
        // `myResult`'s own name-based fallback — see `MatchRepository`.
        let myResult: Bool? = mePlayer.flatMap {
            MatchRepository(modelContext: modelContext).myResult(for: $0, in: match)
        }
        let scoreText: String = {
            if match.matchFormat == .bestOfOne, let onlyGame = games.first {
                return "\(onlyGame.teamAFinalScore) - \(onlyGame.teamBFinalScore)"
            }
            return "\(teamAGames) - \(teamBGames)"
        }()
        let title = VStack(alignment: .leading, spacing: 4) {
            Text("\(teamAName) vs \(teamBName)")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityIdentifier("\(teamAName) vs \(teamBName)")
            Text(match.completedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        let badge = Group {
            if let myResult {
                Text(myResult ? "W" : "L")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(myResult ? .green : .red)
                    .frame(width: resultBadgeSize, height: resultBadgeSize)
                    .background(myResult ? Color.green.opacity(0.2) : Color.red.opacity(0.2), in: Circle())
                    .accessibilityLabel(AccessibilityText.resultWord(didWin: myResult))
            }
        }
        // A best-of-1 match's "games won" score is always 1-0 or 0-1 -
        // true but uninformative on every single row. Showing the
        // actual point score instead tells a reader something new;
        // best-of-3/5 still show the meaningful games-won tally.
        let score = Text(scoreText)
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(.primary)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Too wide for one line at accessibility sizes: the title on
                // top, the result badge and score beneath it.
                VStack(alignment: .leading, spacing: 6) {
                    title
                    HStack(spacing: 12) {
                        badge
                        score
                    }
                }
            } else {
                HStack(spacing: 12) {
                    title
                    Spacer()
                    badge
                    // A fixed trailing-aligned width (not just natural
                    // sizing) - "0 - 11" and "11 - 6" are different widths,
                    // which otherwise shifts the W/L badge left/right from
                    // row to row instead of sitting in a straight column.
                    score
                        .frame(width: scoreColumnWidth, alignment: .trailing)
                }
            }
        }
    }

    private func loadMatches() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            matches = try repository.fetchMatchHistory()
            mePlayer = try repository.fetchMePlayer()
            loadError = nil
            // An edit (or deletion) can leave the filtered player in no match
            // at all; clear the filter instead of showing an empty list that
            // names nobody.
            if let filterPlayerID, !availableFilterPlayers.contains(where: { $0.id == filterPlayerID }) {
                self.filterPlayerID = nil
            }
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
