import SwiftUI
import SwiftData
import PickleballKit

struct MatchSetupView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    @Environment(\.modelContext) private var modelContext
    // Bumped whenever a suggestion chip's player is deleted. Deleting a
    // SavedPlayer via `repository.deleteSavedPlayer` mutates SwiftData
    // directly and doesn't touch any @State the body reads, so without this,
    // SwiftUI has no reason to re-run `suggestionChips` and the just-removed
    // chip would keep showing (stale) until some unrelated state changed.
    @State private var suggestionsVersion = 0

    @State private var playMode: PlayMode = .doubles
    @State private var scoringFormatKind: ScoringFormatKind = .sideOut
    @State private var rallyFreeze = false
    @State private var winningScore: WinningScore = .eleven
    @State private var winByTwo = true
    @State private var matchFormat: MatchFormat = .bestOfOne
    @State private var teamAPlayer1 = ""
    @State private var teamAPlayer1ID: UUID?
    @State private var teamAPlayer2 = ""
    @State private var teamAPlayer2ID: UUID?
    @State private var teamBPlayer1 = ""
    @State private var teamBPlayer1ID: UUID?
    @State private var teamBPlayer2 = ""
    @State private var teamBPlayer2ID: UUID?
    @State private var coinFlipResult: Team?
    @State private var isShowingPaywall = false

    private enum ScoringFormatKind: String, CaseIterable, Identifiable {
        case sideOut = "Side-Out"
        case rally = "Rally"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $playMode) {
                    Text("Singles").tag(PlayMode.singles)
                    Text("Doubles").tag(PlayMode.doubles)
                }
                .pickerStyle(.segmented)
            }

            Section("Scoring Format") {
                Picker("Format", selection: $scoringFormatKind) {
                    ForEach(ScoringFormatKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                if scoringFormatKind == .rally {
                    Toggle("Win game point on serve only (freeze)", isOn: $rallyFreeze)
                }
            }

            Section("Win Condition") {
                Picker("Win Score", selection: $winningScore) {
                    ForEach(WinningScore.allCases, id: \.self) { score in
                        Text("\(score.rawValue)").tag(score)
                    }
                }
                Toggle("Win by 2", isOn: $winByTwo)
            }

            Section("Match Format") {
                Picker("Best of", selection: $matchFormat) {
                    ForEach(MatchFormat.allCases, id: \.self) { format in
                        Text("Best of \(format.rawValue)").tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Team A") {
                TextField(playMode == .doubles ? "Player 1" : "Player Name", text: trackedTextBinding(text: $teamAPlayer1, selectedID: $teamAPlayer1ID))
                    .accessibilityIdentifier("Team A Player Name")
                suggestionChips(for: $teamAPlayer1, selectedID: $teamAPlayer1ID)
                if playMode == .doubles {
                    TextField("Player 2", text: trackedTextBinding(text: $teamAPlayer2, selectedID: $teamAPlayer2ID))
                        .accessibilityIdentifier("Team A Player 2 Name")
                    suggestionChips(for: $teamAPlayer2, selectedID: $teamAPlayer2ID)
                }
            }

            Section("Team B") {
                TextField(playMode == .doubles ? "Player 1" : "Player Name", text: trackedTextBinding(text: $teamBPlayer1, selectedID: $teamBPlayer1ID))
                    .accessibilityIdentifier("Team B Player Name")
                suggestionChips(for: $teamBPlayer1, selectedID: $teamBPlayer1ID)
                if playMode == .doubles {
                    TextField("Player 2", text: trackedTextBinding(text: $teamBPlayer2, selectedID: $teamBPlayer2ID))
                        .accessibilityIdentifier("Team B Player 2 Name")
                    suggestionChips(for: $teamBPlayer2, selectedID: $teamBPlayer2ID)
                }
            }

            Section("First Serve") {
                Button(coinFlipResult == nil ? "Flip Coin" : "Flip Again") {
                    coinFlipResult = CoinFlip.flip()
                }
                // Identifier stays "Flip Coin" regardless of the label toggling to
                // "Flip Again" — plain SwiftUI Button(String) doesn't set its
                // accessibility identifier to match its label by default, so
                // XCUITest lookups need an explicit, stable identifier.
                .accessibilityIdentifier("Flip Coin")
                if let coinFlipResult {
                    Text("\(teamDisplayName(for: coinFlipResult)) serves first")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Start Match") {
                    if activeMatchController.canStartNewMatch {
                        startMatch()
                    } else {
                        isShowingPaywall = true
                    }
                }
                .disabled(coinFlipResult == nil)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("Start Match")
            }
        }
        .navigationTitle("New Match")
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
    }

    private func teamDisplayName(for team: Team) -> String {
        team == .teamA ? combinedName(teamAPlayer1, teamAPlayer2) : combinedName(teamBPlayer1, teamBPlayer2)
    }

    /// Both names are trimmed, and EITHER being blank falls back to the other
    /// alone — the previous version only checked `player2`, so a doubles team
    /// with a blank Player 1 produced a leading " & ".
    private func combinedName(_ player1: String, _ player2: String) -> String {
        let p1 = player1.trimmingCharacters(in: .whitespacesAndNewlines)
        let p2 = player2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard playMode == .doubles else { return p1 }
        switch (p1.isEmpty, p2.isEmpty) {
        case (false, false): return "\(p1) & \(p2)"
        case (true, false): return p2
        default: return p1
        }
    }

    /// Wraps a name field's binding so that any edit the user TYPES (as
    /// opposed to a suggestion-chip tap, which writes the underlying
    /// `$teamXPlayerN` binding directly together with `selectedID`)
    /// clears `selectedID`. This is what lets `startMatch()` trust
    /// "selectedID is non-nil" to mean "the text still exactly matches a
    /// specific SavedPlayer the user selected," not merely "the text
    /// happens to match some saved name."
    private func trackedTextBinding(text: Binding<String>, selectedID: Binding<UUID?>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { newValue in
                text.wrappedValue = newValue
                selectedID.wrappedValue = nil
            }
        )
    }

    private func startMatch() {
        guard let firstServingTeam = coinFlipResult else { return }
        let scoringFormat: ScoringFormat = scoringFormatKind == .sideOut ? .sideOut : .rally(freeze: rallyFreeze)
        let configuration = GameConfiguration(
            playMode: playMode,
            scoringFormat: scoringFormat,
            winningScore: winningScore,
            winByTwo: winByTwo
        )
        let repository = MatchRepository(modelContext: modelContext)
        // Prefers the exact SavedPlayer the user selected via a
        // suggestion chip (re-verified against the current text, in case
        // anything slipped past `trackedTextBinding`'s invalidation) over
        // a fresh name-based upsert — this is what correctly disambiguates
        // two different SavedPlayers that happen to share a name (the
        // spec's "Two Mikes" case), instead of an arbitrary name lookup.
        func resolvedPlayer(name: String, selectedID: UUID?) -> SavedPlayer? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let selectedID,
               let existing = try? repository.fetchAllSavedPlayers().first(where: { $0.id == selectedID }),
               existing.name.caseInsensitiveCompare(trimmed) == .orderedSame {
                return existing
            }
            return try? repository.upsertSavedPlayer(name: name)
        }
        func resolvedPlayers(_ pairs: (String, UUID?)...) -> [SavedPlayer] {
            // Dedupe by id: a doubles side with the same name typed into
            // both fields must not double-count that one player in
            // `timesPlayed`/stats attribution.
            var seen = Set<UUID>()
            return pairs.compactMap { resolvedPlayer(name: $0.0, selectedID: $0.1) }
                .filter { seen.insert($0.id).inserted }
        }
        let teamAPlayers = playMode == .doubles
            ? resolvedPlayers((teamAPlayer1, teamAPlayer1ID), (teamAPlayer2, teamAPlayer2ID))
            : resolvedPlayers((teamAPlayer1, teamAPlayer1ID))
        let teamBPlayers = playMode == .doubles
            ? resolvedPlayers((teamBPlayer1, teamBPlayer1ID), (teamBPlayer2, teamBPlayer2ID))
            : resolvedPlayers((teamBPlayer1, teamBPlayer1ID))
        activeMatchController.startNewMatch(
            configuration: configuration,
            matchFormat: matchFormat,
            firstServingTeam: firstServingTeam,
            teamAName: combinedName(teamAPlayer1, teamAPlayer2),
            teamBName: combinedName(teamBPlayer1, teamBPlayer2),
            teamAPlayers: teamAPlayers,
            teamBPlayers: teamBPlayers
        )
    }

    @ViewBuilder
    private func suggestionChips(for field: Binding<String>, selectedID: Binding<UUID?>) -> some View {
        let query = field.wrappedValue
        if !query.isEmpty {
            let repository = MatchRepository(modelContext: modelContext)
            let matches = (try? repository.suggestedPlayers(matching: query)) ?? []
            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(matches, id: \.id) { player in
                            Button(player.name) {
                                field.wrappedValue = player.name
                                selectedID.wrappedValue = player.id
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("PlayerSuggestion.\(player.name)")
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    try? repository.deleteSavedPlayer(player)
                                    suggestionsVersion += 1
                                }
                                .accessibilityIdentifier("Remove")
                            }
                        }
                    }
                }
                .id(suggestionsVersion)
            }
        }
    }
}
