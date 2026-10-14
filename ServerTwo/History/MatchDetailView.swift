import SwiftUI
import PickleballKit

struct MatchDetailView: View {
    let match: MatchRecord
    let onRematch: (RematchRequest) -> Void

    private var teamAName: String {
        (match.teamSides ?? []).first { $0.team == .teamA }?.displayName ?? "Team A"
    }
    private var teamBName: String {
        (match.teamSides ?? []).first { $0.team == .teamB }?.displayName ?? "Team B"
    }
    private var orderedGames: [GameRecord] {
        (match.games ?? []).sorted { $0.gameNumber < $1.gameNumber }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                resultCard
                ForEach(orderedGames) { game in
                    gameCard(game)
                }
            }
            .padding()
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
                MatchRecapShareButton(match: match)
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(teamAName) vs \(teamBName)")
                    .font(.title2.bold())
                Spacer()
                Text(match.completedAt, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                    Text("Winner: \(match.winningTeam == .teamA ? teamAName : teamBName)")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.3), in: Capsule())

                if let formatSummary {
                    Text(formatSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gameCard(_ game: GameRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Game \(game.gameNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
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

            Divider()
                .overlay(Color.primary.opacity(0.12))

            VStack(spacing: 10) {
                ForEach(game.orderedPoints) { point in
                    HStack(spacing: 10) {
                        Text("\(point.sequenceNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .leading)
                        Circle()
                            .fill(point.scoringTeam == .teamA ? Color.accentColor : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("\(point.scoringTeam == .teamA ? teamAName : teamBName) scored")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(point.teamAScoreAfter)-\(point.teamBScoreAfter)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
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
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(score)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(won ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}
