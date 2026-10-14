import SwiftUI
import SwiftData
import PickleballKit

struct StatsSummaryView: View {
    let matches: [MatchRecord]
    let mePlayer: SavedPlayer?
    let repository: MatchRepository

    var body: some View {
        // Each column hugs its own content width (statColumn has no
        // `.frame(maxWidth: .infinity)`) instead of being forced into an
        // equal third — three equal-width slots left a short value like
        // "3" floating in space its own content didn't need, while a wide
        // one like "44 - 27" crowded its slot's edges. The flanking
        // Spacers center the whole (naturally-sized) group as a unit, so
        // it re-centers itself automatically as values grow more digits,
        // rather than needing a fixed width tuned for today's numbers.
        //
        // `.top` (not the default `.center`) — "Points For/Against" wraps
        // to two lines while the other two labels stay on one, and
        // center-aligning the whole HStack let that taller column pull
        // its own number down out of line with the other two, reading as
        // randomly misaligned.
        HStack(alignment: .top, spacing: 16) {
            Spacer(minLength: 0)
            statColumn(title: "Matches", value: "\(matches.count)")
            if let mePlayer {
                let record = repository.personalRecord(for: mePlayer, in: matches)
                statDivider
                statColumn(title: "Your Record", value: "\(record.wins) - \(record.losses)")
                statDivider
                statColumn(title: "Points For/Against", value: "\(record.pointsFor) - \(record.pointsAgainst)")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // An explicit height and color rather than Divider's own defaults —
    // its default separator color is tuned for a system background, and
    // this card can sit against a plain black background in dark mode
    // where that default reads as too low-contrast to notice.
    private var statDivider: some View {
        Divider()
            .frame(height: 32)
            .overlay(Color.primary.opacity(0.15))
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

#Preview {
    StatsSummaryView(matches: [], mePlayer: nil, repository: MatchRepository(modelContext: ModelContext(try! PersistenceContainer.makeInMemoryContainer())))
}
