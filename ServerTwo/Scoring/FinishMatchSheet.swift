import SwiftUI
import PickleballKit

/// Replaces a plain `.alert("Finish Match?", ...)` — finishing a match is a
/// bigger moment than a generic system dialog treats it as, and this app
/// already has an established, reliable pattern for a confirmation `.sheet`
/// (see `ManagePlayersView`'s rename UI).
struct FinishMatchSheet: View {
    let teamAName: String
    let teamBName: String
    let isBestOfOne: Bool
    let teamAScore: Int
    let teamBScore: Int
    let teamAGames: Int
    let teamBGames: Int
    let winningTeam: Team
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("\(winningTeamName) Wins!")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            scoreRow
            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Confirm Finish") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("Confirm Finish")
            }
        }
        .padding()
        .presentationDetents([.height(320)])
    }

    private var winningTeamName: String {
        winningTeam == .teamA ? teamAName : teamBName
    }

    private var scoreRow: some View {
        HStack(spacing: 24) {
            teamScoreColumn(name: teamAName, value: isBestOfOne ? teamAScore : teamAGames, highlighted: winningTeam == .teamA)
            Text("-")
                .font(.title.bold())
                .foregroundStyle(.secondary)
            teamScoreColumn(name: teamBName, value: isBestOfOne ? teamBScore : teamBGames, highlighted: winningTeam == .teamB)
        }
    }

    private func teamScoreColumn(name: String, value: Int, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(highlighted ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    FinishMatchSheet(
        teamAName: "Delon",
        teamBName: "Yi",
        isBestOfOne: true,
        teamAScore: 11,
        teamBScore: 6,
        teamAGames: 1,
        teamBGames: 0,
        winningTeam: .teamA,
        onConfirm: {}
    )
}
