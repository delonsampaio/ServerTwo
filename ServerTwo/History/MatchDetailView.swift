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
        List {
            Section("Result") {
                Text("\(teamAName) vs \(teamBName)")
                    .font(.headline)
                Text("Winner: \(match.winningTeam == .teamA ? teamAName : teamBName)")
                Text(match.completedAt, style: .date)
                    .foregroundStyle(.secondary)
            }

            ForEach(orderedGames) { game in
                Section("Game \(game.gameNumber)") {
                    Text("\(teamAName) \(game.teamAFinalScore) - \(game.teamBFinalScore) \(teamBName)")
                        .font(.subheadline.bold())
                    ForEach(game.orderedPoints) { point in
                        Text("\(point.sequenceNumber). \(point.scoringTeam == .teamA ? teamAName : teamBName) scored — \(point.teamAScoreAfter)-\(point.teamBScoreAfter)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Match Detail")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MatchRecapShareButton(match: match)
            }
        }
    }
}
