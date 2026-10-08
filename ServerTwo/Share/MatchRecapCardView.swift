import SwiftUI
import PickleballKit

struct MatchRecapCardView: View {
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
    private var teamAGamesWon: Int { orderedGames.filter { $0.winningTeam == .teamA }.count }
    private var teamBGamesWon: Int { orderedGames.filter { $0.winningTeam == .teamB }.count }
    private var winnerName: String { match.winningTeam == .teamA ? teamAName : teamBName }

    var body: some View {
        VStack(spacing: 16) {
            Text("🏆 \(winnerName) Wins")
                .font(.title2.bold())

            HStack(spacing: 32) {
                VStack {
                    Text(teamAName).font(.headline)
                    Text("\(teamAGamesWon)").font(.system(size: 48, weight: .bold, design: .rounded))
                }
                Text("-").font(.largeTitle)
                VStack {
                    Text(teamBName).font(.headline)
                    Text("\(teamBGamesWon)").font(.system(size: 48, weight: .bold, design: .rounded))
                }
            }

            Text("Server Two")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 360, height: 360)
        .background(.background)
    }
}

#Preview {
    MatchRecapCardView(match: MatchRecord(
        startedAt: .now,
        completedAt: .now,
        matchFormat: .bestOfThree,
        winningTeam: .teamA,
        configurationData: Data()
    ))
}
