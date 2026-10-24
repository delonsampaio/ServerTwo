import SwiftUI
import PickleballKit

struct MatchDetailView: View {
    let match: MatchRecord
    let onRematch: (RematchRequest) -> Void

    @State private var isEditingPlayers = false
    // Bumped when Edit Players saves: the match models are already updated by
    // then, but this screen's content (and the share image) is refreshed
    // explicitly because SwiftData observation did not re-render it reliably.
    @State private var refreshRevision = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // 36 pt, 24 pt and 6 pt at the default text size; they scale with Dynamic
    // Type (the score digits stop at 52 pt and never wrap).
    @ScaledMetric(relativeTo: .largeTitle) private var gameScoreSize: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var sequenceColumnWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var scorerDotSize: CGFloat = 6
    private let gameScoreSizeCap: CGFloat = 52

    private var teamAName: String {
        (match.teamSides ?? []).first { $0.team == .teamA }?.displayName ?? "Team A"
    }
    private var teamBName: String {
        (match.teamSides ?? []).first { $0.team == .teamB }?.displayName ?? "Team B"
    }
    private var orderedGames: [GameRecord] {
        (match.games ?? []).sorted { $0.gameNumber < $1.gameNumber }
    }

    var durationText: String? {
        let interval = match.completedAt.timeIntervalSince(match.startedAt)
        // Exactly zero means "no timing data" (Quick Log sets both
        // timestamps identically) — distinct from a genuinely short live
        // match, which still reports "< 1 min" below.
        guard interval > 0 else { return nil }
        guard interval >= 60 else { return "< 1 min" }
        return Duration.seconds(interval)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Two games are indistinguishable for "closest" purposes only when
    /// they share BOTH their margin and their total points — not merely
    /// the same margin. A plain `Set` of margins would make the
    /// margin-tie-break rule below unreachable for any 2-game match
    /// where both games happen to share a margin (e.g. 11-9 and 15-13,
    /// margin 2 both times): `Set([2, 2])` has one element, so a guard
    /// on distinct margins alone would return `nil` before ever reaching
    /// the tiebreaker, contradicting the spec's own worked example of
    /// exactly that case.
    private struct ClosenessKey: Hashable {
        let margin: Int
        let totalPoints: Int
    }

    var closestGameID: GameRecord.ID? {
        guard orderedGames.count > 1 else { return nil }
        let keys = Set(orderedGames.map {
            ClosenessKey(
                margin: abs($0.teamAFinalScore - $0.teamBFinalScore),
                totalPoints: $0.teamAFinalScore + $0.teamBFinalScore
            )
        })
        guard keys.count > 1 else { return nil }

        return orderedGames.min { lhs, rhs in
            let lhsMargin = abs(lhs.teamAFinalScore - lhs.teamBFinalScore)
            let rhsMargin = abs(rhs.teamAFinalScore - rhs.teamBFinalScore)
            if lhsMargin != rhsMargin { return lhsMargin < rhsMargin }
            let lhsTotal = lhs.teamAFinalScore + lhs.teamBFinalScore
            let rhsTotal = rhs.teamAFinalScore + rhs.teamBFinalScore
            return lhsTotal > rhsTotal
        }?.id
    }

    var longestGameID: GameRecord.ID? {
        guard orderedGames.count > 1 else { return nil }
        guard orderedGames.allSatisfy({ $0.completedAt != nil }) else { return nil }

        var previousCheckpoint = match.startedAt
        var longest: (id: GameRecord.ID, duration: TimeInterval)?
        for game in orderedGames {
            let completedAt = game.completedAt!
            let duration = completedAt.timeIntervalSince(previousCheckpoint)
            if longest == nil || duration > longest!.duration {
                longest = (game.id, duration)
            }
            previousCheckpoint = completedAt
        }
        return longest?.id
    }

    /// "Singles • Best of 1", etc. `nil` if the stored rules can't be
    /// decoded — not expected for a match this app itself saved, but a
    /// failed decode should just omit the metadata rather than crash or
    /// show garbage.
    private var formatSummary: String? {
        guard let configuration = try? JSONDecoder().decode(GameConfiguration.self, from: match.configurationData) else {
            return nil
        }
        let mode = configuration.playMode == .singles ? "Singles" : "Doubles"
        let bestOf = "Best of \(match.matchFormat.rawValue)"
        switch configuration.scoringFormat {
        case .sideOut:
            return "\(mode) • \(bestOf)"
        case .rally:
            return "\(mode) • \(bestOf) • Rally"
        }
    }

    private var matchMetadataText: String? {
        // `joined(separator:)` always returns a (possibly empty) String,
        // which implicitly wraps into a non-nil String? — without this
        // guard, "both formatSummary and durationText are nil" would
        // render an empty Text row instead of none at all.
        let parts = [formatSummary, durationText].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                resultCard
                ForEach(orderedGames) { game in
                    gameCard(game)
                }
            }
            .padding()
            .id(refreshRevision)
        }
        .sheet(isPresented: $isEditingPlayers) {
            EditMatchPlayersSheet(match: match)
        }
        // Posted only by a successful save, so Cancel rebuilds nothing.
        .onReceive(NotificationCenter.default.publisher(for: .matchPlayersEdited)) { _ in
            refreshRevision += 1
        }
        .navigationTitle("Match Detail")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Only offered when the match's stored rules can still be
                // decoded and both sides are present — not expected to
                // ever fail for a match this app itself saved, but a
                // failed decode should silently omit the button rather
                // than offer a rematch that can't actually be built.
                if let request = RematchRequest(match: match) {
                    Button("Rematch") {
                        onRematch(request)
                    }
                    .accessibilityIdentifier("Rematch")
                }
            }
            // Liquid Glass merges adjacent trailing toolbar items into one
            // shared capsule by default, which made "Rematch" and the
            // Share icon read as a single "Share Rematch" button instead
            // of two distinct actions. A `ToolbarSpacer` is the system's
            // own way to force a visual break between groups — manually
            // drawing a background on each button instead would fight
            // Liquid Glass's own chrome the same way an explicit
            // `.buttonStyle` on a toolbar button does elsewhere in this
            // app (it renders as a bare "..." there).
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                MatchRecapShareButton(match: match, refreshKey: refreshRevision)
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveStack(rowAlignment: .firstTextBaseline, columnAlignment: .leading, spacing: 8) {
                Text("\(teamAName) vs \(teamBName)")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                // In the card next to the title, not in the toolbar (which
                // already holds Rematch and Share). The sheet saves straight
                // into `match`; `refreshRevision` refreshes this content.
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                    Text(match.completedAt, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Button {
                        isEditingPlayers = true
                    } label: {
                        // Outlined text in `.primary` rather than
                        // `PillButtonStyle`: the audit's contrast check fails
                        // the accent blue on this card, and it also fails
                        // this button once a pencil icon sits next to the
                        // text (verified: text alone passes), so there is no
                        // icon. Same 44 pt tap area (`tapAreaLabel`).
                        Text("Edit Players")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1))
                            .tapAreaLabel(9)
                    }
                    .buttonStyle(.plain)
                    .tapAreaGiveBack(9)
                    // Needed for the audit, not just for VoiceOver: without an explicit
                    // label the audit evaluates the whole button element (outline and
                    // tap padding included) and fails its contrast; with it the same
                    // button passes (verified both ways).
                    .accessibilityLabel("Edit Players")
                    .accessibilityHint("Change who played this match")
                    .accessibilityIdentifier("Edit Players")
                }
            }
            AdaptiveStack(columnAlignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .accessibilityHidden(true)
                    Text("Winner: \(match.winningTeam == .teamA ? teamAName : teamBName)")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.3), in: Capsule())

                if let matchMetadataText {
                    Text(matchMetadataText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gameCard(_ game: GameRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AdaptiveStack(columnAlignment: .leading, spacing: 6) {
                Text("Game \(game.gameNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                if game.id == closestGameID {
                    Text("Closest Game")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }
                if game.id == longestGameID {
                    Text("Longest Game")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue, in: Capsule())
                }
            }
            // Names and scores are visually separated (name small/secondary,
            // score large/bold) rather than run together in one sentence —
            // a single "TeamName Score - Score TeamName" line reads as
            // crowded, especially with doubles' longer combined names.
            // Each column spans half the card's width (not just its own
            // content's width), so the two sides read as a balanced
            // scoreboard instead of a block bunched into the top-left
            // corner with the rest of the card empty. No separator between
            // them — flush-left and flush-right on opposite edges of the
            // card already reads as two sides without needing a "-" to
            // say so, and with that much empty space between them a lone
            // hyphen just looked stranded in the middle of the card.
            HStack(alignment: .lastTextBaseline) {
                gameScoreColumn(name: teamAName, score: game.teamAFinalScore, won: game.winningTeam == .teamA, alignment: .leading)
                gameScoreColumn(name: teamBName, score: game.teamBFinalScore, won: game.winningTeam == .teamB, alignment: .trailing)
            }

            // A quick-logged game's GameRecord.points stays empty (there's
            // no live play to log) — the divider and point list would
            // otherwise render with nothing underneath.
            if !game.orderedPoints.isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.12))

                VStack(spacing: 10) {
                    ForEach(game.orderedPoints) { point in
                        HStack(spacing: 10) {
                            Text("\(point.sequenceNumber)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: sequenceColumnWidth, alignment: .leading)
                            Circle()
                                .fill(point.scoringTeam == .teamA ? Color.accentColor : Color.orange)
                                .frame(width: scorerDotSize, height: scorerDotSize)
                                .accessibilityHidden(true)
                            Text("\(point.scoringTeam == .teamA ? teamAName : teamBName) scored")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(point.teamAScoreAfter)-\(point.teamBScoreAfter)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        // One VoiceOver stop per point instead of three
                        // (sequence, scorer, running score).
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(AccessibilityText.pointRowLabel(
                            sequence: point.sequenceNumber,
                            scorerName: point.scoringTeam == .teamA ? teamAName : teamBName,
                            scoreAfter: "\(point.teamAScoreAfter) to \(point.teamBScoreAfter)"
                        ))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gameScoreColumn(name: String, score: Int, won: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
            Text("\(score)")
                .font(.system(size: max(36, min(gameScoreSize, gameScoreSizeCap)), weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(won ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}
