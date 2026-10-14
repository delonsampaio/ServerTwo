import SwiftUI
import SwiftData
import PhotosUI
import PickleballKit

struct ManagePlayersView: View {
    let onRematch: (RematchRequest) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var players: [SavedPlayer] = []
    @State private var loadError: Error?
    @State private var renamingPlayer: SavedPlayer?
    @State private var renameText: String = ""
    @State private var isAddingPlayer = false
    @State private var newPlayerName: String = ""

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
                                .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .accessibilityIdentifier("PlayerRow.\(player.name)")
                            if player.isMe {
                                Text("Me")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                                    .accessibilityIdentifier("Me.\(player.name)")
                            }
                        }
                        Spacer()
                        // An explicit, non-default style is what keeps
                        // these buttons from interfering with each other
                        // or with the background NavigationLink below —
                        // without one, two plain Buttons packed into one
                        // List row get overlapping default tap regions and
                        // a tap aimed at one can fire the other's action
                        // (observed: tapping "Set as Me" opened "Rename").
                        // `.bordered` (not `.borderless`) also gives each
                        // button its own visible pill chrome, so two of
                        // them sitting next to each other read as distinct
                        // tappable buttons instead of one run-on line of
                        // blue text. `.fixedSize()` keeps a longer name
                        // from squeezing these into wrapping/truncating.
                        Button("Rename") {
                            renameText = player.name
                            renamingPlayer = player
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityIdentifier("Rename.\(player.name)")
                        if !player.isMe {
                            Button("Set as Me") {
                                setMe(player)
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                            .accessibilityIdentifier("SetMe.\(player.name)")
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    // The real NavigationLink lives here, hidden, instead
                    // of wrapping just the name — as a visible row child it
                    // only spanned the name's own width, so the List's
                    // auto-added disclosure chevron rendered right after
                    // it (floating in the middle of the row, pointing into
                    // "Rename") rather than at the row's actual trailing
                    // edge. A hidden NavigationLink in the background
                    // keeps the full row tappable for navigation while the
                    // Buttons above it, as normal foreground siblings,
                    // still take tap priority over whatever's behind them
                    // — and the chevron above is now a plain Image placed
                    // exactly where it visually belongs.
                    .background(
                        NavigationLink(destination: PlayerDetailView(player: player, onRematch: onRematch)) { EmptyView() }
                            .opacity(0)
                    )
                }
                .onDelete(perform: deletePlayers)
            }
        }
        .navigationTitle("Manage Players")
        .toolbar {
            // Previously the only way to create a player was to start a
            // match — this lets someone pre-populate their regular group,
            // or set themselves as "Me," before ever playing a first game.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newPlayerName = ""
                    isAddingPlayer = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("Add Player")
            }
        }
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
        // Same sheet-not-alert rationale as the rename sheet above.
        .sheet(isPresented: $isAddingPlayer) {
            VStack(spacing: 16) {
                Text("Add Player")
                    .font(.headline)
                TextField("Name", text: $newPlayerName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("NewPlayerField")
                HStack {
                    Button("Cancel", role: .cancel) {
                        isAddingPlayer = false
                    }
                    .accessibilityIdentifier("Cancel")
                    Spacer()
                    Button("Save") {
                        addPlayer(named: newPlayerName)
                        isAddingPlayer = false
                    }
                    .accessibilityIdentifier("Save")
                }
            }
            .padding()
            .presentationDetents([.height(180)])
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

    // `upsertSavedPlayer` (not a raw insert) so typing a name that already
    // exists reuses that player instead of creating an exact duplicate —
    // the same rule every other player-creation path in the app follows.
    private func addPlayer(named name: String) {
        let repository = MatchRepository(modelContext: modelContext)
        _ = try? repository.upsertSavedPlayer(name: name)
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
        ManagePlayersView(onRematch: { _ in })
    }
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
