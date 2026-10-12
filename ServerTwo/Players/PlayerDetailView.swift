import SwiftUI
import SwiftData
import PickleballKit

/// Reached by tapping a row in `ManagePlayersView`. `personalRecord` already
/// works for any `SavedPlayer`, not just "Me" — this view is just a UI entry
/// point onto infrastructure the personal-stats feature already built.
struct PlayerDetailView: View {
    let player: SavedPlayer

    @Environment(\.modelContext) private var modelContext
    @State private var record: (wins: Int, losses: Int, pointsFor: Int, pointsAgainst: Int)?
    @State private var loadError: Error?

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    PlayerAvatarView(player: player, size: 80)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section {
                if let record {
                    LabeledContent("Record") {
                        Text("\(record.wins) - \(record.losses)")
                            .accessibilityIdentifier("PlayerDetail.Record")
                    }
                    LabeledContent("Points For/Against") {
                        Text("\(record.pointsFor) - \(record.pointsAgainst)")
                            .accessibilityIdentifier("PlayerDetail.PointsForAgainst")
                    }
                } else if loadError != nil {
                    ContentUnavailableView(
                        "Couldn't Load Stats",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Pull down to try again.")
                    )
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle(player.name)
        .task { loadRecord() }
        .refreshable { loadRecord() }
    }

    private func loadRecord() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            let matches = try repository.fetchMatchHistory()
            record = repository.personalRecord(for: player, in: matches)
            loadError = nil
        } catch {
            loadError = error
        }
    }
}

#Preview {
    let container = try! PersistenceContainer.makeInMemoryContainer()
    let context = ModelContext(container)
    let player = SavedPlayer(name: "Delon")
    context.insert(player)
    return NavigationStack {
        PlayerDetailView(player: player)
    }
    .modelContainer(container)
}
