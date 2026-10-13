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
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                Text("Winner: \(match.winningTeam == .teamA ? teamAName : teamBName)")
                    .font(.subheadline.bold())
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.yellow.opacity(0.3), in: Capsule())
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
            // Matches the name-above-score pattern already used in
            // ScoringView and FinishMatchSheet.
            HStack(spacing: 8) {
                gameScoreColumn(name: teamAName, score: game.teamAFinalScore)
                Text("-")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                gameScoreColumn(name: teamBName, score: game.teamBFinalScore)
            }

            VStack(spacing: 10) {
                ForEach(game.orderedPoints) { point in
                    HStack(spacing: 10) {
                        Text("\(point.sequenceNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        Text("\(point.scoringTeam == .teamA ? teamAName : teamBName) scored")
                            .font(.subheadline)
                        Spacer()
                        Text("\(point.teamAScoreAfter)-\(point.teamBScoreAfter)")
                            .font(.subheadline.monospacedDigit().bold())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gameScoreColumn(name: String, score: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(score)")
                .font(.title.bold())
        }
    }
}
