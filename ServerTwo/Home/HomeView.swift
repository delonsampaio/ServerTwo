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
    let onRematch: (RematchRequest) -> Void
    let onQuickStart: (QuickStartRequest) -> Void

    @State private var matches: [MatchRecord] = []
    @State private var mePlayer: SavedPlayer?
    @State private var frequentPlayers: [SavedPlayer] = []
    @State private var selectedQuickStartPlayers: [SavedPlayer] = []
    @State private var loadError: Error?
    @State private var isShowingPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    if let lastMatch = matches.first {
                        lastMatchCard(lastMatch)
                        quickStartRow
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Match")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(teamAName) vs \(teamBName)")
                        .font(.headline)
                    Text("\(teamAGames) - \(teamBGames)")
                        .font(.title2.bold())
                }
                Spacer()
                // Only offered when the match's stored rules can still be
                // decoded and both sides are present — not expected to ever
                // fail for a match this app itself just saved, but a failed
                // decode should silently omit the button rather than offer
                // a rematch that can't actually be built.
                if let request = RematchRequest(match: match) {
                    Button("Rematch") {
                        onRematch(request)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("Rematch")
                }
            }
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
                let streak = repository.winStreak(for: mePlayer, in: matches)
                let form = repository.recentForm(for: mePlayer, in: matches)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your Record")
                            .font(.subheadline)
                            .accessibilityIdentifier("Your Record")
                        Spacer()
                        Text("\(record.wins) - \(record.losses)")
                            .font(.headline)
                            .accessibilityIdentifier("YourRecordValue")
                    }
                    if !form.isEmpty || streak > 0 {
                        // Grouped together, not next to the record number
                        // above — both the streak and the W/L dots are
                        // "how am I doing lately" (momentum), a different
                        // thing from the lifetime record, and a plain
                        // number sitting right beside another plain number
                        // read ambiguously as one run-together figure.
                        HStack(spacing: 6) {
                            // Only shown while it's actually something to
                            // be proud of — a "streak" of 0 isn't a
                            // streak, it's just noise right after a loss.
                            if streak > 0 {
                                Text("🔥 \(streak)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange, in: Capsule())
                                    .accessibilityIdentifier("WinStreak")
                            }
                            // Most-recent-first, matching how "how am I
                            // doing lately" is naturally read.
                            ForEach(Array(form.enumerated()), id: \.offset) { _, didWin in
                                Text(didWin ? "W" : "L")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(didWin ? Color.green : Color.red, in: Circle())
                            }
                        }
                        .accessibilityIdentifier("RecentForm")
                    }
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

    /// Top 3-4 most recently/frequently played saved players, reusing the
    /// exact ranking `MatchSetupView`'s suggestion chips already use (an
    /// empty query returns everyone, recency-then-frequency ranked).
    /// Tapping toggles selection rather than navigating immediately, so
    /// picking 2-4 known regulars takes one trip to Setup, not one
    /// navigation per player. "Start" only appears once something's
    /// selected.
    @ViewBuilder
    private var quickStartRow: some View {
        if !frequentPlayers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Quick Start")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !selectedQuickStartPlayers.isEmpty {
                        Button("Start (\(selectedQuickStartPlayers.count))") {
                            let players = selectedQuickStartPlayers.map {
                                QuickStartRequest.PlayerSlot(name: $0.name, savedPlayerID: $0.id)
                            }
                            selectedQuickStartPlayers = []
                            onQuickStart(QuickStartRequest(players: players))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("Start Quick Start Selection")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(frequentPlayers.prefix(4)), id: \.id) { player in
                            let isSelected = selectedQuickStartPlayers.contains { $0.id == player.id }
                            Button {
                                toggleQuickStartSelection(player)
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack(alignment: .topTrailing) {
                                        PlayerAvatarView(player: player, size: 44)
                                            .overlay(
                                                Circle().stroke(isSelected ? Color.green : Color.clear, lineWidth: 3)
                                            )
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.green, .white)
                                                .offset(x: 4, y: -4)
                                        }
                                    }
                                    Text(player.name)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 60)
                                }
                            }
                            .buttonStyle(.plain)
                            // Only 4 player slots exist in Setup (doubles'
                            // max) — once 4 are selected, further taps on
                            // an unselected chip would have nowhere to go.
                            .disabled(!isSelected && selectedQuickStartPlayers.count >= 4)
                            .accessibilityIdentifier("QuickStart.\(player.name)")
                        }
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func toggleQuickStartSelection(_ player: SavedPlayer) {
        if let index = selectedQuickStartPlayers.firstIndex(where: { $0.id == player.id }) {
            selectedQuickStartPlayers.remove(at: index)
        } else if selectedQuickStartPlayers.count < 4 {
            selectedQuickStartPlayers.append(player)
        }
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
            frequentPlayers = (try? repository.suggestedPlayers(matching: "")) ?? []
            loadError = nil
        } catch {
            matches = []
            loadError = error
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(onNewMatch: {}, onRematch: { _ in }, onQuickStart: { _ in })
    }
    .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
