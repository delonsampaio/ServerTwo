import SwiftUI
import SwiftData
import PickleballKit

/// Changes who played a completed match: fixes a wrong pick or fills in a
/// blank left at save time. Only the sides' players and names change; scores,
/// winner, rules and the point log stay as they were (see
/// `MatchRepository.updateSides`).
struct EditMatchPlayersSheet: View {
    let match: MatchRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var teamA: [PlayerSlotEntry]
    @State private var teamB: [PlayerSlotEntry]
    @State private var savedPlayers: [SavedPlayer] = []
    @State private var saveError: String?
    @FocusState private var focusedSlot: SlotID?

    private struct SlotID: Hashable {
        let team: Team
        let index: Int
    }

    init(match: MatchRecord) {
        self.match = match
        let isDoubles = (try? JSONDecoder().decode(GameConfiguration.self, from: match.configurationData))
            .map { $0.playMode == .doubles }
        func initialSlots(for team: Team) -> [PlayerSlotEntry] {
            let side = (match.teamSides ?? []).first { $0.team == team }
            let linked = (side?.orderedPlayers ?? []).map { PlayerSlotEntry(name: $0.name, savedPlayerID: $0.id) }
            let current = EditMatchPlayersValidation.currentEntries(
                linked: linked, displayName: side?.displayName ?? "", team: team
            )
            return EditMatchPlayersValidation.slots(
                current,
                count: EditMatchPlayersValidation.slotCount(isDoubles: isDoubles, currentPlayerCount: current.count)
            )
        }
        _teamA = State(initialValue: initialSlots(for: .teamA))
        _teamB = State(initialValue: initialSlots(for: .teamB))
    }

    private var problem: String? {
        EditMatchPlayersValidation.problem(teamA: teamA, teamB: teamB, savedPlayers: savedPlayers)
    }

    var body: some View {
        // A plain ScrollView at every size (not `AdaptiveScroll`, which only
        // scrolls at accessibility sizes): this sheet holds up to four fields
        // plus suggestion chips, and the keyboard covers the lower ones even
        // at the default text size. Nothing here needs to be centred or
        // stretched, which is what `AdaptiveScroll` exists to protect.
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Edit Players")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                teamSection(title: "Team A", team: .teamA, slots: $teamA)
                teamSection(title: "Team B", team: .teamB, slots: $teamB)
                if let reason = problem ?? saveError {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("EditPlayers.Problem")
                }
                AdaptiveStack(spacing: 12) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("EditPlayers.Cancel")
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(problem != nil)
                        .accessibilityHint(problem ?? "")
                        .accessibilityIdentifier("EditPlayers.Save")
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .adaptiveSheetDetents(height: 560)
        // A stale "Couldn't save" must not resurface after the user changed anything.
        .onChange(of: teamA) { saveError = nil }
        .onChange(of: teamB) { saveError = nil }
        // The reason appears below the fields, away from the focused one, so
        // VoiceOver would not otherwise notice it.
        .onChange(of: problem) { _, newProblem in
            if let newProblem { VoiceOverAnnouncement.post(newProblem) }
        }
        .task { loadSavedPlayers() }
    }

    private func teamSection(title: String, team: Team, slots: Binding<[PlayerSlotEntry]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(slots.wrappedValue.indices, id: \.self) { index in
                slotField(team: team, index: index, entry: slots[index])
            }
        }
    }

    private func slotField(team: Team, index: Int, entry: Binding<PlayerSlotEntry>) -> some View {
        let teamName = team == .teamA ? "Team A" : "Team B"
        let slotID = SlotID(team: team, index: index)
        let slotCount = (team == .teamA ? teamA : teamB).count
        let prompt = slotCount > 1 ? "Player \(index + 1)" : "Player Name"
        return VStack(alignment: .leading, spacing: 6) {
            TextField(prompt, text: Binding(
                get: { entry.wrappedValue.name },
                set: { newValue in
                    guard newValue != entry.wrappedValue.name else { return }
                    // Typing detaches the slot from the picked player — the
                    // same rule as match setup — so a picked id is only ever
                    // kept while the field still shows that player's name.
                    entry.wrappedValue = PlayerSlotEntry(name: newValue)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($focusedSlot, equals: slotID)
            // The keyboard covers Save and Cancel, and a sheet has no
            // toolbar to hang a keyboard "Done" on, so Return dismisses it.
            .submitLabel(.done)
            .onSubmit { focusedSlot = nil }
            .accessibilityLabel("\(teamName), player \(index + 1)")
            .accessibilityIdentifier("EditPlayers.\(team == .teamA ? "TeamA" : "TeamB").Slot\(index + 1)")
            suggestionChips(for: entry, isFocused: focusedSlot == slotID)
        }
    }

    /// Shown while the field is focused or holds unselected text, and hidden
    /// once a chip is picked (otherwise the chosen player's own chip would
    /// keep showing) — the same behaviour as the chips in match setup.
    @ViewBuilder
    private func suggestionChips(for entry: Binding<PlayerSlotEntry>, isFocused: Bool) -> some View {
        let query = entry.wrappedValue.name
        if entry.wrappedValue.savedPlayerID == nil, isFocused || !query.isEmpty {
            let matches = (try? MatchRepository(modelContext: modelContext).suggestedPlayers(matching: query)) ?? []
            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(matches, id: \.id) { player in
                            Button {
                                entry.wrappedValue = PlayerSlotEntry(name: player.name, savedPlayerID: player.id)
                            } label: {
                                HStack(spacing: 6) {
                                    PlayerAvatarView(player: player, size: 20)
                                    Text(player.name)
                                }
                            }
                            .buttonStyle(PillButtonStyle())
                            .accessibilityIdentifier("EditPlayers.Suggestion.\(player.name)")
                        }
                    }
                }
            }
        }
    }

    private func loadSavedPlayers() {
        savedPlayers = (try? MatchRepository(modelContext: modelContext).fetchAllSavedPlayers()) ?? []
    }

    private func save() {
        do {
            try MatchRepository(modelContext: modelContext).updateSides(of: match, teamA: teamA, teamB: teamB)
            NotificationCenter.default.post(name: .matchPlayersEdited, object: nil)
            dismiss()
        } catch let error as MatchRepositoryError {
            if case .duplicatePlayer(let name) = error {
                saveError = "\(name) is listed more than once."
            } else {
                saveError = "Couldn't save these players. Please try again."
            }
        } catch {
            saveError = "Couldn't save these players. Please try again."
        }
    }
}

