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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Today's sizes at the default text size; they scale with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var badgeScale: CGFloat = 1
    @ScaledMetric(relativeTo: .largeTitle) private var scoreDigitSize: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var dividerHeight: CGFloat = 36
    private let scoreDigitSizeCap: CGFloat = 56
    private let badgeScaleCap: CGFloat = 1.4

    var body: some View {
        AdaptiveScroll {
            VStack(spacing: 20) {
                trophyBadge
                Text("\(winningTeamName) Wins!")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                scoreRow
                // Full-width, equal-width action row (not small pills with
                // empty space around them) — these are the two things a
                // thumb needs to reach without looking closely right after a
                // match ends. Native `.glass`/`.glassProminent` (not
                // hand-drawn fills) for true Liquid Glass material; the
                // `.frame(maxWidth: .infinity)` goes on each label, not the
                // Button itself — on the Button it only widens the tap
                // target, leaving the style's own background hugging the
                // text.
                AdaptiveStack(spacing: 12) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)

                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("Confirm Finish")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.accentColor)
                    .accessibilityIdentifier("Confirm Finish")
                }
                .controlSize(.large)
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
        .adaptiveSheetDetents(height: 320)
        .presentationBackground(.clear)
    }

    private var trophyBadge: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.15))
                .overlay(Circle().strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1))
                .frame(width: 60 * max(1, min(badgeScale, badgeScaleCap)), height: 60 * max(1, min(badgeScale, badgeScaleCap)))
            Image(systemName: "trophy.fill")
                .font(.system(size: 28 * max(1, min(badgeScale, badgeScaleCap)), weight: .bold))
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
                .frame(width: 1, height: dividerHeight)
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.secondaryText)
            Text("\(value)")
                .font(.system(size: max(36, min(scoreDigitSize, scoreDigitSizeCap)), weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(highlighted ? Color.primary : Color.secondaryText)
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
