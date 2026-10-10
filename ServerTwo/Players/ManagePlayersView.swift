import SwiftUI
import SwiftData
import PickleballKit

struct ManagePlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var players: [SavedPlayer] = []
    @State private var loadError: Error?
    @State private var renamingPlayer: SavedPlayer?
    @State private var renameText: String = ""

    var body: some View {
        List {
            if players.isEmpty, loadError == nil {
                ContentUnavailableView(
                    "No Saved Players Yet",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Players you enter when starting a match are saved here automatically.")
                )
            } else {
                ForEach(players, id: \.id) { player in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(player.name)
                                .accessibilityIdentifier("PlayerRow.\(player.name)")
                            if player.isMe {
                                Text("Me")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("Me.\(player.name)")
                            }
                        }
                        Spacer()
                        // `.borderless` makes each button its own hit-test
                        // target. Without it, two plain Buttons packed into
                        // one List row get overlapping default tap regions
                        // and a tap aimed at one can fire the other's action
                        // (observed: tapping "Set as Me" opened "Rename").
                        Button("Rename") {
                            renameText = player.name
                            renamingPlayer = player
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("Rename.\(player.name)")
                        if !player.isMe {
                            Button("Set as Me") {
                                setMe(player)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("SetMe.\(player.name)")
                        }
                    }
                }
                .onDelete(perform: deletePlayers)
            }
        }
        .navigationTitle("Manage Players")
        .task { loadPlayers() }
        // A `.sheet`, not `.alert`, hosts the rename form. On this OS a
        // `.alert` with an embedded `TextField` renders through a
        // UICollectionView-backed UIAlertController whose "Save" button
        // tap was observed (via XCUITest) to neither fire its action
        // closure nor dismiss the alert — the Alert/TextField/CollectionView
        // combination appears to not reliably deliver the tap. A sheet
        // with ordinary SwiftUI controls doesn't go through that code
        // path, and it still exposes the same "Name" text field and
        // "Save"/"Cancel" buttons the UI tests look for.
        .sheet(
            isPresented: Binding(
                get: { renamingPlayer != nil },
                set: { isPresented in if !isPresented { renamingPlayer = nil } }
            )
        ) {
            // Captured once, when the sheet is built, so it stays valid
            // for the lifetime of this presentation regardless of when
            // `renamingPlayer` itself gets cleared during dismissal.
            if let player = renamingPlayer {
                VStack(spacing: 16) {
                    Text("Rename Player")
                        .font(.headline)
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel", role: .cancel) {
                            renamingPlayer = nil
                        }
                        Spacer()
                        Button("Save") {
                            rename(player, to: renameText)
                            renamingPlayer = nil
                        }
                    }
                }
                .padding()
                .presentationDetents([.height(180)])
            }
        }
    }

    private func loadPlayers() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            players = try repository.fetchAllSavedPlayers().sorted { $0.name < $1.name }
            loadError = nil
        } catch {
            players = []
            loadError = error
        }
    }

    private func setMe(_ player: SavedPlayer) {
        let repository = MatchRepository(modelContext: modelContext)
        try? repository.setMePlayer(player)
        loadPlayers()
    }

    private func rename(_ player: SavedPlayer, to newName: String) {
        let repository = MatchRepository(modelContext: modelContext)
        try? repository.renameSavedPlayer(player, to: newName)
        loadPlayers()
    }

    private func deletePlayers(at offsets: IndexSet) {
        let repository = MatchRepository(modelContext: modelContext)
        for index in offsets {
            try? repository.deleteSavedPlayer(players[index])
        }
        loadPlayers()
    }
}

#Preview {
    NavigationStack {
        ManagePlayersView()
    }
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
