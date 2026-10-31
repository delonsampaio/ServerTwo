import SwiftUI
import PickleballKit

/// The slots for the current play mode (one a side in singles, two in
/// doubles). Optional: with nobody chosen a match starts with "Team A" and
/// "Team B". Changes save at once, like the Rules sheet.
struct PlayersSheet: View {
    @Binding var lastPlayers: LastUsedPlayers
    let playMode: PlayMode
    let directory: WatchPlayerDirectory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(WatchPlayerSelection.slots(for: playMode), id: \.self) { slot in
                    NavigationLink {
                        PlayerPickerView(slot: slot, playMode: playMode, lastPlayers: $lastPlayers, directory: directory)
                    } label: {
                        SlotRow(
                            title: slot.title(for: playMode),
                            name: lastPlayers.selection.entry(at: slot)?.name
                        )
                    }
                    .accessibilityIdentifier("Slot \(slot.team == .teamA ? "A" : "B")\(slot.index + 1)")
                }
                if !lastPlayers.selection.isEmpty {
                    Button("Clear All", role: .destructive) { lastPlayers.selection.clearAll() }
                        .accessibilityIdentifier("Clear Players")
                        .accessibilityHint("Starts the next match as Team A and Team B")
                }
            }
            .navigationTitle("Players")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: lastPlayers.selection) { lastPlayers.save() }
    }
}

/// A slot: which spot it is, and who is in it (or that it is empty).
private struct SlotRow: View {
    let title: String
    let name: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.secondaryText)
            Text(name ?? "Choose")
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(name == nil ? Color.secondaryText : Color.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(name ?? "empty")")
        .accessibilityHint("Opens the player list")
    }
}

/// Who goes in one slot: Me first, then the iPhone's saved players, a row to
/// type a new name (one tap opens the system text input: dictation, Scribble or
/// keyboard) and Clear. Players already in another slot are shown disabled.
struct PlayerPickerView: View {
    let slot: WatchPlayerSelection.Slot
    let playMode: PlayMode
    @Binding var lastPlayers: LastUsedPlayers
    let directory: WatchPlayerDirectory
    @Environment(\.dismiss) private var dismiss

    @State private var typedName = ""
    /// The phone's "listed more than once" line, shown when a typed name is
    /// refused.
    @State private var refusal: String?

    private var current: SyncedPlayerRef? { lastPlayers.selection.entry(at: slot) }

    var body: some View {
        List {
            if let refusal {
                Text(refusal)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("Duplicate Player Reason")
            }
            ForEach(directory.options) { option in
                optionRow(option)
            }
            TextField("New player", text: $typedName)
                .submitLabel(.done)
                .onSubmit(addTypedName)
                .accessibilityIdentifier("New Player")
                .accessibilityHint("Opens text input for a new player name")
            if current != nil {
                Button("Clear", role: .destructive) {
                    lastPlayers.selection.clear(slot)
                    dismiss()
                }
                .accessibilityIdentifier("Clear Slot")
            }
        }
        .navigationTitle(slot.title(for: playMode))
    }

    private func optionRow(_ option: WatchPlayerOption) -> some View {
        let isUsed = lastPlayers.selection.isUsed(option.entry, excluding: slot, mode: playMode)
        return Button { choose(option.entry) } label: {
            HStack(spacing: 4) {
                Text(option.entry.name).lineLimit(1)
                Spacer(minLength: 0)
                if option.isMe {
                    Text("Me").font(.caption2).foregroundStyle(Color.secondaryText)
                }
                if option.entry == current {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
            }
        }
        .disabled(isUsed)
        .accessibilityLabel(option.isMe ? "\(option.entry.name), you" : option.entry.name)
        .accessibilityAddTraits(option.entry == current ? .isSelected : [])
        .accessibilityHint(isUsed ? "Already playing in another spot" : "")
    }

    private func choose(_ entry: SyncedPlayerRef) {
        switch lastPlayers.selection.assign(entry, to: slot, mode: playMode) {
        case .assigned:
            dismiss()
        case .refused(let reason):
            refusal = reason
        }
    }

    /// A name equal to a cached player (any case) picks that player; any other
    /// is a new name, remembered for the next match until the phone's list
    /// replaces it. A refused name is not remembered.
    private func addTypedName() {
        let text = typedName
        typedName = ""
        guard let entry = directory.resolve(typedName: text) else { return }
        switch lastPlayers.selection.assign(entry, to: slot, mode: playMode) {
        case .assigned:
            directory.remember(entry)
            dismiss()
        case .refused(let reason):
            refusal = reason
        }
    }
}
