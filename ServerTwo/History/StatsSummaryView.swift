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
                Divider()
                statColumn(title: "Your Record", value: "\(record.wins) - \(record.losses)")
                Divider()
                statColumn(title: "Points For/Against", value: "\(record.pointsFor) - \(record.pointsAgainst)")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    StatsSummaryView(matches: [], mePlayer: nil, repository: MatchRepository(modelContext: ModelContext(try! PersistenceContainer.makeInMemoryContainer())))
}
