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
            trophyBadge
            Text("\(winningTeamName) Wins!")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            scoreRow
            // Full-width, equal-width action row (not small pills with
            // empty space around them) — these are the two things a
            // thumb needs to reach without looking closely right after a
            // match ends.
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Confirm Finish")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityIdentifier("Confirm Finish")
            }
        }
        .padding()
        // An opaque elevated surface of our own — the sheet's own default
        // system material is translucent, which let the live Scoring
        // screen's Timeout buttons and the tab bar bleed through as
        // blurry blobs right behind this card.
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, y: -4)
                .ignoresSafeArea()
        )
        .presentationDetents([.height(320)])
        .presentationBackground(.clear)
    }

    private var trophyBadge: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.15))
                .overlay(Circle().strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1))
                .frame(width: 60, height: 60)
            Image(systemName: "trophy.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.yellow)
        }
    }

    private var winningTeamName: String {
        winningTeam == .teamA ? teamAName : teamBName
    }

    private var scoreRow: some View {
        // An inset box with a vertical divider (not two columns floating
        // in open space with a stray "-" between them) anchors the final
        // score as one cohesive unit instead of three separately-placed
        // elements.
        HStack(spacing: 0) {
            teamScoreColumn(name: teamAName, value: isBestOfOne ? teamAScore : teamAGames, highlighted: winningTeam == .teamA)
            Rectangle()
                .fill(.primary.opacity(0.12))
                .frame(width: 1, height: 36)
            teamScoreColumn(name: teamBName, value: isBestOfOne ? teamBScore : teamBGames, highlighted: winningTeam == .teamB)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func teamScoreColumn(name: String, value: Int, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
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
