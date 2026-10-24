import SwiftUI
import SwiftData
import PickleballKit

/// Reached by tapping a row in `ManagePlayersView`. `personalRecord` already
/// works for any `SavedPlayer`, not just "Me" — this view is just a UI entry
/// point onto infrastructure the personal-stats feature already built.
struct PlayerDetailView: View {
    let player: SavedPlayer
    let onRematch: (RematchRequest) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var record: (wins: Int, losses: Int, pointsFor: Int, pointsAgainst: Int)?
    @State private var recentForm: [Bool] = []
    @State private var matches: [MatchRecord] = []
    @State private var loadError: Error?
    @State private var mePlayer: SavedPlayer?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // 22 pt and 54 pt at the default text size; they scale with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var resultBadgeSize: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var scoreColumnWidth: CGFloat = 54
    @ScaledMetric(relativeTo: .title2) private var statDividerHeight: CGFloat = 32
    @State private var chemistry: (asPartner: (wins: Int, losses: Int)?, asOpponent: (wins: Int, losses: Int)?)?

    var body: some View {
        List {
            // Centered avatar + name + Me badge + match count, grouped as
            // one profile header instead of a lone avatar floating above
            // an unrelated left-aligned nav title.
            Section {
                VStack(spacing: 8) {
                    PlayerAvatarView(player: player, size: 88)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 2))
                        .shadow(radius: 4, y: 2)
                    HStack(spacing: 6) {
                        Text(player.name)
                            .font(.title2.weight(.bold))
                        if player.isMe {
                            Text("Me")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                        }
                    }
                    if let record {
                        let total = record.wins + record.losses
                        Text("\(total) Match\(total == 1 ? "" : "es") Played")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                if let record {
                    let total = record.wins + record.losses
                    let winPct = total > 0 ? Int((Double(record.wins) / Double(total) * 100).rounded()) : 0
                    // Content-sized columns centered as a group (same
                    // technique as StatsSummaryView) rather than forced
                    // equal thirds, plus a matching divider style.
                    // Three columns side by side no longer fit at accessibility
                    // sizes, so they stack (without the dividers).
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 12) {
                                statColumn(value: "\(record.wins) - \(record.losses)", label: "Record")
                                    .accessibilityIdentifier("PlayerDetail.Record")
                                statColumn(value: "\(winPct)%", label: "Win Rate")
                                statColumn(value: "\(record.pointsFor) - \(record.pointsAgainst)", label: "Points For/Against")
                                    .accessibilityIdentifier("PlayerDetail.PointsForAgainst")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            HStack(alignment: .top, spacing: 16) {
                                Spacer(minLength: 0)
                                statColumn(value: "\(record.wins) - \(record.losses)", label: "Record")
                                    .accessibilityIdentifier("PlayerDetail.Record")
                                statDivider
                                statColumn(value: "\(winPct)%", label: "Win Rate")
                                statDivider
                                statColumn(value: "\(record.pointsFor) - \(record.pointsAgainst)", label: "Points For/Against")
                                    .accessibilityIdentifier("PlayerDetail.PointsForAgainst")
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    if showsChemistry, let chemistry {
                        if let asPartner = chemistry.asPartner {
                            Divider()
                            HStack {
                                Text("As Your Partner")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(asPartner.wins) - \(asPartner.losses)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            .padding(.vertical, 4)
                        }
                        if let asOpponent = chemistry.asOpponent {
                            Divider()
                            HStack {
                                Text("As Your Opponent")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(asOpponent.wins) - \(asOpponent.losses)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if !recentForm.isEmpty {
                        Divider()
                        AdaptiveStack(columnAlignment: .leading, spacing: 8) {
                            Text("Recent Form")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // The strip below carries this same label.
                                .accessibilityHidden(true)
                            // Oldest-to-newest, left to right — matches
                            // HomeView's own recent-form dots.
                            HStack(spacing: 8) {
                                ForEach(Array(recentForm.reversed().enumerated()), id: \.offset) { _, didWin in
                                    Text(didWin ? "W" : "L")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: resultBadgeSize, height: resultBadgeSize)
                                        .background(didWin ? Color.green : Color.red, in: Circle())
                                }
                            }
                            // One stop that reads the results in the order they
                            // are displayed, instead of a row of "W"/"L" letters.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Recent form")
                            .accessibilityValue(AccessibilityText.recentFormValue(Array(recentForm.reversed())))
                            .accessibilityIdentifier("RecentForm")
                        }
                        .padding(.vertical, 4)
                    }
                } else if loadError != nil {
                    ContentUnavailableView(
                        "Couldn't Load Stats",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Pull down to try again.")
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            if !matches.isEmpty {
                Section("Matches") {
                    ForEach(matches) { match in
                        // Destination-based (not `NavigationLink(value:)` +
                        // `.navigationDestination(for:)`), matching
                        // ManagePlayersView's own player-row navigation —
                        // value-based navigation from inside a view that
                        // was itself reached via an older destination-
                        // based push silently did nothing on tap, even
                        // with the destination registered at the
                        // Settings stack's root. Tried that; it didn't
                        // hold up under a real (asserted, not just
                        // screenshotted) re-check. This row has no
                        // competing buttons of its own, so there's no
                        // reason to fight for the plain, reliable style.
                        NavigationLink(destination: MatchDetailView(match: match, onRematch: onRematch)) {
                            matchRow(match)
                        }
                    }
                }
            }
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { loadRecord() }
        .refreshAfterPlayersEdited { loadRecord() }
        .refreshable { loadRecord() }
    }

    private var showsChemistry: Bool {
        mePlayer != nil && mePlayer?.id != player.id
    }

    private var statDivider: some View {
        Divider()
            .frame(height: statDividerHeight)
            .overlay(Color.primary.opacity(0.15))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
        }
    }

    // Same scannable row as MatchHistoryListView's rows, computed from
    // this player's own perspective (not whatever "mePlayer" might be
    // set elsewhere) — this screen can be reached for any saved player.
    private func matchRow(_ match: MatchRecord) -> some View {
        let teamAName = (match.teamSides ?? []).first { $0.team == .teamA }?.displayName ?? "Team A"
        let teamBName = (match.teamSides ?? []).first { $0.team == .teamB }?.displayName ?? "Team B"
        let games = (match.games ?? []).sorted { $0.gameNumber < $1.gameNumber }
        let teamAGames = games.filter { $0.winningTeam == .teamA }.count
        let teamBGames = games.filter { $0.winningTeam == .teamB }.count
        let result = MatchRepository(modelContext: modelContext).myResult(for: player, in: match)
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
            Text(match.completedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        let badge = Group {
            if let result {
                Text(result ? "W" : "L")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(result ? .green : .red)
                    .frame(width: resultBadgeSize, height: resultBadgeSize)
                    .background(result ? Color.green.opacity(0.2) : Color.red.opacity(0.2), in: Circle())
                    .accessibilityLabel(AccessibilityText.resultWord(didWin: result))
            }
        }
        let score = Text(scoreText)
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(.primary)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
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
                    score
                        .frame(width: scoreColumnWidth, alignment: .trailing)
                }
            }
        }
    }

    private func loadRecord() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            let allMatches = try repository.fetchMatchHistory()
            record = repository.personalRecord(for: player, in: allMatches)
            recentForm = repository.recentForm(for: player, in: allMatches)
            matches = allMatches.filter { repository.myResult(for: player, in: $0) != nil }
            mePlayer = try repository.fetchMePlayer()
            if let mePlayer, mePlayer.id != player.id {
                chemistry = repository.chemistry(between: mePlayer, and: player, in: allMatches)
            } else {
                chemistry = nil
            }
            loadError = nil
        } catch {
            loadError = error
        }
    }
}

#Preview {
    let container = try! PersistenceContainer.makeInMemoryContainer()
    let context = ModelContext(container)
    let player = SavedPlayer(name: "Delon")
    context.insert(player)
    return NavigationStack {
        PlayerDetailView(player: player, onRematch: { _ in })
    }
    .modelContainer(container)
}
