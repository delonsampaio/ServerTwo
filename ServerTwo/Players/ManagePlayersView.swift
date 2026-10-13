import SwiftUI
import SwiftData
import PhotosUI
import PickleballKit

struct ManagePlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var players: [SavedPlayer] = []
    @State private var loadError: Error?
    @State private var renamingPlayer: SavedPlayer?
    @State private var renameText: String = ""

    var body: some View {
        List {
            if players.isEmpty, loadError != nil {
                ContentUnavailableView(
                    "Couldn't Load Players",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Pull down to try again.")
                )
            } else if players.isEmpty {
                ContentUnavailableView(
                    "No Saved Players Yet",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Players you enter when starting a match are saved here automatically.")
                )
            } else {
                ForEach(players, id: \.id) { player in
                    HStack {
                        // `.borderless` on the buttons below is what keeps
                        // this NavigationLink from swallowing their taps —
                        // the same mechanism (own hit-test region) already
                        // used to fix Rename/Set as Me interfering with
                        // each other; a NavigationLink's row-wide tap
                        // target respects it the same way.
                        // A write-only PhotosPicker: tapping the avatar
                        // opens the picker directly (no separate "Edit
                        // Photo" step), and there's no need for per-row
                        // @State since the binding's `get` is never
                        // actually read back.
                        PhotosPicker(
                            selection: Binding(
                                get: { nil },
                                set: { (newItem: PhotosPickerItem?) in
                                    guard let newItem else { return }
                                    Task { await setPhoto(for: player, from: newItem) }
                                }
                            ),
                            matching: .images
                        ) {
                            PlayerAvatarView(player: player, size: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("PhotoPicker.\(player.name)")
                        .contextMenu {
                            if player.photoData != nil {
                                Button("Remove Photo", role: .destructive) {
                                    removePhoto(for: player)
                                }
                                .accessibilityIdentifier("RemovePhoto.\(player.name)")
                            }
                        }

                        NavigationLink {
                            PlayerDetailView(player: player)
                        } label: {
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
                        }
                        Spacer()
                        // An explicit, non-default style is what keeps
                        // this NavigationLink/these buttons from
                        // interfering with each other — without one, two
                        // plain Buttons packed into one List row get
                        // overlapping default tap regions and a tap aimed
                        // at one can fire the other's action (observed:
                        // tapping "Set as Me" opened "Rename"). `.bordered`
                        // (not `.borderless`) also gives each button its
                        // own visible pill chrome, so two of them sitting
                        // next to each other read as distinct tappable
                        // buttons instead of one run-on line of blue text.
                        Button("Rename") {
                            renameText = player.name
                            renamingPlayer = player
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("Rename.\(player.name)")
                        if !player.isMe {
                            Button("Set as Me") {
                                setMe(player)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
            // `renamingPlayer` is read fresh here, so this `if let` DOES
            // re-evaluate (and would fail) the instant `renamingPlayer`
            // becomes nil. It works anyway because dismissal animates the
            // sheet out over time — by the time this closure would next
            // run with a nil `renamingPlayer`, the sheet is already gone.
            // This is not a capture; don't rely on this timing elsewhere.
            if let player = renamingPlayer {
                VStack(spacing: 16) {
                    Text("Rename Player")
                        .font(.headline)
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("RenameField")
                    HStack {
                        Button("Cancel", role: .cancel) {
                            renamingPlayer = nil
                        }
                        .accessibilityIdentifier("Cancel")
                        Spacer()
                        Button("Save") {
                            rename(player, to: renameText)
                            renamingPlayer = nil
                        }
                        .accessibilityIdentifier("Save")
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

    private func setPhoto(for player: SavedPlayer, from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let processed = PlayerPhotoProcessor.process(data) else { return }
        let repository = MatchRepository(modelContext: modelContext)
        try? repository.setPlayerPhoto(player, data: processed)
        loadPlayers()
    }

    private func removePhoto(for player: SavedPlayer) {
        let repository = MatchRepository(modelContext: modelContext)
        try? repository.setPlayerPhoto(player, data: nil)
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
