import SwiftUI
import SwiftData
import PickleballKit

struct StatsSummaryView: View {
    let matches: [MatchRecord]
    let mePlayer: SavedPlayer?
    let repository: MatchRepository

    var body: some View {
        // `.top` (not the default `.center`) — "Points For/Against" wraps
        // to two lines while the other two labels stay on one, and
        // center-aligning the whole HStack let that taller column pull
        // its own number down out of line with the other two, reading as
        // randomly misaligned.
        HStack(alignment: .top) {
            statColumn(title: "Matches", value: "\(matches.count)")
            if let mePlayer {
                let record = repository.personalRecord(for: mePlayer, in: matches)
                Divider()
                statColumn(title: "Your Record", value: "\(record.wins) - \(record.losses)")
                Divider()
                statColumn(title: "Points For/Against", value: "\(record.pointsFor) - \(record.pointsAgainst)")
            }
        }
        // Explicit outer margin, not left to the List row's default inset
        // — "Points For/Against" is the widest value in its column, so
        // without this it sat with noticeably less breathing room against
        // the card's trailing edge than "Matches" had on the leading edge.
        .padding(.horizontal, 8)
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
    StatsSummaryView(matches: [], mePlayer: nil, repository: MatchRepository(modelContext: ModelContext(try! PersistenceContainer.makeInMemoryContainer())))
}
