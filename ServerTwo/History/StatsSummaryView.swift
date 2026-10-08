import SwiftUI
import PickleballKit

struct StatsSummaryView: View {
    let matches: [MatchRecord]

    // "Team A"/"Team B" wins is an honest, simple convention: PickleballKit
    // doesn't track a persistent "my team" identity across matches (each
    // match's teams are independently named), so this reports Team A's
    // record literally rather than guessing which side the viewer was on.
    private var teamAWins: Int { matches.filter { $0.winningTeam == .teamA }.count }
    private var teamBWins: Int { matches.filter { $0.winningTeam == .teamB }.count }

    private var totalPointsForA: Int {
        matches.flatMap { $0.games ?? [] }.reduce(0) { $0 + $1.teamAFinalScore }
    }
    private var totalPointsForB: Int {
        matches.flatMap { $0.games ?? [] }.reduce(0) { $0 + $1.teamBFinalScore }
    }

    var body: some View {
        HStack {
            statColumn(title: "Matches", value: "\(matches.count)")
            Divider()
            statColumn(title: "Team A / Team B Wins", value: "\(teamAWins) - \(teamBWins)")
            Divider()
            statColumn(title: "Points For/Against", value: "\(totalPointsForA) - \(totalPointsForB)")
        }
        .padding(.vertical, 8)
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    StatsSummaryView(matches: [])
}
