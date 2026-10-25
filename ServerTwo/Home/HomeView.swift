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
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Today's fixed sizes at the default text size; they scale with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var resultBadgeSize: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var formDotSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var quickStartScale: CGFloat = 1
    let onNewMatch: () -> Void
    let onRematch: (RematchRequest) -> Void
    let onQuickStart: (QuickStartRequest) -> Void

    @State private var matches: [MatchRecord] = []
    @State private var mePlayer: SavedPlayer?
    @State private var frequentPlayers: [SavedPlayer] = []
    @State private var selectedQuickStartPlayers: [SavedPlayer] = []
    @State private var loadError: Error?
    @State private var isShowingPaywall = false
    // Bumped after Edit Players saved; see `refreshAfterPlayersEdited`.
    @State private var editRevision = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // `hasBeenDeleted`: a delete from another tab can leave this body
                    // running once more with the just-deleted record still in
                    // `matches`; reading its properties (the card and the Pro
                    // share button both do) traps in SwiftData, so it is skipped
                    // by id first (see `MatchDeleted`).
                    if let lastMatch = matches.first, !MatchDeleted.hasBeenDeleted(lastMatch.persistentModelID) {
                        lastMatchCard(lastMatch)
                            .id(editRevision)
                        quickStartRow
                        matchesPlayedCard
                            .id(editRevision)
                        // Share now lives in the Last Match card's own
                        // header once Pro is unlocked — this slot is only
                        // needed for the upsell banner while it's locked.
                        if !activeMatchController.proUnlocked {
                            proUpsellBanner
                        }
                    } else if loadError != nil {
                        ContentUnavailableView(
                            "Couldn't Load History",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Pull down to try again, or just start a new match.")
                        )
                        .padding(.top, 40)
                    } else {
                        Text("Play your first match to see it here.")
                            .foregroundStyle(Color.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                        // A fresh install can reach the purchase in one tap,
                        // before the first match exists.
                        if !activeMatchController.proUnlocked {
                            proUpsellBanner
                        }
                    }
                }
                .padding()
            }
            .refreshable { loadMatches() }

            Button {
                onNewMatch()
            } label: {
                Label("New Match", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.accentColor)
            .controlSize(.large)
            .padding()
            .accessibilityIdentifier("New Match")
        }
        .navigationTitle("Server Two")
        .task { loadMatches() }
        .refreshAfterPlayersEdited(revision: $editRevision) { loadMatches() }
        // The Last Match card and the stats read `matches` directly, so
        // dropping the deleted record here also updates both at once.
        .onMatchDeleted { id in matches = matches.removing(modelID: id) }
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
        // Same treatment as MatchHistoryListView's rows, so this card and
        // History read consistently instead of Home showing a bare
        // "0 - 1" series tally that could be mistaken for a game score.
        let myResult: Bool? = mePlayer.flatMap {
            MatchRepository(modelContext: modelContext).myResult(for: $0, in: match)
        }
        return VStack(alignment: .leading, spacing: 4) {
            AdaptiveStack(rowAlignment: .firstTextBaseline, columnAlignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Match")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(teamAName) vs \(teamBName)")
                        .font(.headline)
                    HStack(spacing: 8) {
                        if let myResult {
                            Text(myResult ? "W" : "L")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(myResult ? Color.winGreenText : Color.errorRed)
                                .frame(width: resultBadgeSize, height: resultBadgeSize)
                                .background((myResult ? Color.winGreen : Color.lossRed).opacity(Color.resultBadgeTintOpacity), in: Circle())
                                .accessibilityLabel(AccessibilityText.resultWord(didWin: myResult))
                        }
                        if match.matchFormat == .bestOfOne, let onlyGame = games.first {
                            Text("\(onlyGame.teamAFinalScore) - \(onlyGame.teamBFinalScore)")
                                .font(.title2.bold())
                        } else {
                            Text("\(teamAGames) - \(teamBGames)")
                                .font(.title2.bold())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    // Only offered when the match's stored rules can still be
                    // decoded and both sides are present — not expected to
                    // ever fail for a match this app itself just saved, but a
                    // failed decode should silently omit the button rather
                    // than offer a rematch that can't actually be built.
                    if let request = RematchRequest(match: match) {
                        Button("Rematch") {
                            onRematch(request)
                        }
                        .buttonStyle(PillButtonStyle())
                        .accessibilityIdentifier("Rematch")
                    }
                    // Lives here (not its own card below) once Pro is
                    // unlocked — a whole extra full-width card just for one
                    // button was more vertical clutter than this match
                    // needed, when it already has a header row with room.
                    if activeMatchController.proUnlocked {
                        MatchRecapShareButton(match: match)
                            .buttonStyle(PillButtonStyle())
                    }
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
                    // Header row: title plus the streak (when there is
                    // one) — keeping the streak up here, not stacked under
                    // the record number below, frees that number to pair
                    // directly with the W/L dots on its own row instead of
                    // leaving a hollow gap across the bottom-right of the
                    // card.
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your Record")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("Your Record")
                        Spacer()
                        // Only shown while it's actually something to be
                        // proud of — a "streak" of 0 isn't a streak, it's
                        // just noise right after a loss.
                        if streak > 0 {
                            Text("🔥 \(streak) streak")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.orangeText)
                                .accessibilityIdentifier("WinStreak")
                                .accessibilityLabel("\(streak) win streak")
                        }
                    }
                    // Content row: the record is the hero metric on the
                    // left, recent form (most-recent-first, matching how
                    // "how am I doing lately" is naturally read) on the
                    // right of the same row.
                    AdaptiveStack(rowAlignment: .lastTextBaseline, columnAlignment: .leading, spacing: 8) {
                        Text("\(record.wins) - \(record.losses)")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("YourRecordValue")
                        if !form.isEmpty {
                            HStack(spacing: 8) {
                                // `form` itself is most-recent-first (see
                                // `recentForm`'s own doc comment) — reversed
                                // here so the dots read oldest-to-newest,
                                // left to right, landing the most recent
                                // result on the right, directly under the
                                // streak badge above it that's describing
                                // that same current momentum.
                                ForEach(Array(form.reversed().enumerated()), id: \.offset) { _, didWin in
                                    Text(didWin ? "W" : "L")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: formDotSize, height: formDotSize)
                                        .background(didWin ? Color.winGreen : Color.lossRed, in: Circle())
                                }
                            }
                            // One stop that reads the results in the order
                            // they are displayed, instead of a row of "W"/"L"
                            // letters.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Recent form")
                            .accessibilityValue(AccessibilityText.recentFormValue(Array(form.reversed())))
                            .accessibilityIdentifier("RecentForm")
                        }
                    }
                }
            } else {
                HStack {
                    Text("Matches Played")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(matches.count)")
                        .font(.title2.bold())
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
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if !selectedQuickStartPlayers.isEmpty {
                        Button {
                            let players = selectedQuickStartPlayers.map {
                                QuickStartRequest.PlayerSlot(name: $0.name, savedPlayerID: $0.id)
                            }
                            selectedQuickStartPlayers = []
                            onQuickStart(QuickStartRequest(players: players))
                        } label: {
                            Text("Start (\(selectedQuickStartPlayers.count))")
                        }
                        .buttonStyle(PillButtonStyle())
                        .accessibilityIdentifier("Start Quick Start Selection")
                    }
                }
                // Up to 4 players: a plain, evenly-distributed row (not a
                // horizontal ScrollView) — that many comfortably fits
                // every supported iPhone width, and a ScrollView's content
                // hugs its own natural size regardless of the container's
                // width, so it can't actually spread fewer-than-4 avatars
                // out even if asked to. Past 4, an evenly-distributed row
                // would squeeze every avatar instead, so it switches to a
                // horizontal scroll at a fixed per-item width instead —
                // sized so a 5th player visibly peeks off the right edge,
                // a natural cue that the row scrolls without needing a
                // visible scrollbar.
                let quickStartPlayers = Array(frequentPlayers.prefix(8))
                // At accessibility sizes the scaled avatars no longer fit four
                // to a row, so it always uses the scrolling row.
                if quickStartPlayers.count <= 4, !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 16) {
                        ForEach(quickStartPlayers, id: \.id) { player in
                            quickStartItem(player)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 6)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(quickStartPlayers, id: \.id) { player in
                                quickStartItem(player)
                                    .frame(width: 68 * max(1, min(quickStartScale, 1.6)))
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func quickStartItem(_ player: SavedPlayer) -> some View {
        // The selected checkmark badge pokes above the avatar's own
        // bounds (offset upward) — without top padding on the row above,
        // it would sit flush against the card's own top edge.
        let isSelected = selectedQuickStartPlayers.contains { $0.id == player.id }
        return Button {
            toggleQuickStartSelection(player)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    PlayerAvatarView(player: player, size: 44)
                        .overlay(
                            Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                        )
                        .overlay(
                            Circle().stroke(isSelected ? Color.winGreen : Color.clear, lineWidth: 3)
                        )
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.winGreen, .white)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(player.name)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        // Only 4 player slots exist in Setup (doubles' max) — once 4 are
        // selected, further taps on an unselected chip would have
        // nowhere to go.
        .disabled(!isSelected && selectedQuickStartPlayers.count >= 4)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("QuickStart.\(player.name)")
    }

    private func toggleQuickStartSelection(_ player: SavedPlayer) {
        if let index = selectedQuickStartPlayers.firstIndex(where: { $0.id == player.id }) {
            selectedQuickStartPlayers.remove(at: index)
        } else if selectedQuickStartPlayers.count < 4 {
            selectedQuickStartPlayers.append(player)
        }
    }

    /// Consistent with every other paywall trigger in the app. Only shown
    /// while locked — once Pro is unlocked, the share shortcut this slot
    /// used to hold moved into the Last Match card's own header instead,
    /// so there's nothing left to show here.
    private var proUpsellBanner: some View {
        Button {
            isShowingPaywall = true
        } label: {
            HStack {
                Image(systemName: "lock.fill")
                Text(storeManager.displayPrice.map { "Unlock Server Two Pro — \($0)" } ?? "Unlock Server Two Pro")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .padding()
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("Home Unlock Pro Banner")
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

// Debug only: the preview store is the debug fake, which Release builds do not contain.
#if DEBUG
#Preview {
    NavigationStack {
        HomeView(onNewMatch: {}, onRematch: { _ in }, onQuickStart: { _ in })
    }
    .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
    .environment(StoreManager.preview)
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
#endif
