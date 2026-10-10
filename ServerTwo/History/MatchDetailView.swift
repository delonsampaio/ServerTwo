import SwiftUI
import PickleballKit

struct MatchDetailView: View {
    let match: MatchRecord

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
                MatchRecapShareButton(match: match)
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(teamAName) vs \(teamBName)")
                .font(.title2.bold())
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text("Winner: \(match.winningTeam == .teamA ? teamAName : teamBName)")
                    .font(.headline)
            }
            Text(match.completedAt, style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gameCard(_ game: GameRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Game \(game.gameNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(teamAName) \(game.teamAFinalScore) - \(game.teamBFinalScore) \(teamBName)")
                .font(.title3.bold())

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
}
