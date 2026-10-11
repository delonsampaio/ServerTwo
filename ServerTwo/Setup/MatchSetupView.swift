import SwiftUI
import SwiftData
import PickleballKit

struct MatchSetupView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    @Environment(\.modelContext) private var modelContext

    /// Set by a "Rematch" button on Home or a match's History detail
    /// screen, consumed once via `.onChange` below, which is what makes
    /// this work even when `MatchSetupView` was already on screen (an
    /// `.onAppear`/init-based one-shot wouldn't fire in that case, since
    /// nothing recreates this view).
    let pendingRematch: RematchRequest?
    let onPrefillConsumed: () -> Void

    /// Same one-shot mechanism as `pendingRematch`, but only ever touches
    /// Team A's first player — everything else (rules, Team B, coin flip)
    /// is left exactly as the user already had it.
    let pendingQuickStart: QuickStartRequest?
    let onQuickStartConsumed: () -> Void

    init(
        pendingRematch: RematchRequest? = nil,
        onPrefillConsumed: @escaping () -> Void = {},
        pendingQuickStart: QuickStartRequest? = nil,
        onQuickStartConsumed: @escaping () -> Void = {}
    ) {
        self.pendingRematch = pendingRematch
        self.onPrefillConsumed = onPrefillConsumed
        self.pendingQuickStart = pendingQuickStart
        self.onQuickStartConsumed = onQuickStartConsumed
    }

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
    @State private var trackTimeouts = true
    @State private var matchFormat: MatchFormat = .bestOfOne
    @State private var teamAPlayer1 = ""
    @State private var teamAPlayer1ID: UUID?
    @State private var teamAPlayer2 = ""
    @State private var teamAPlayer2ID: UUID?
    @State private var teamBPlayer1 = ""
    @State private var teamBPlayer1ID: UUID?
    @State private var teamBPlayer2 = ""
    @State private var teamBPlayer2ID: UUID?
    @State private var isShowingPaywall = false
    @FocusState private var focusedField: NameField?

    private enum ScoringFormatKind: String, CaseIterable, Identifiable {
        case sideOut = "Side-Out"
        case rally = "Rally"
        var id: String { rawValue }
    }

    private enum NameField: Hashable {
        case teamAPlayer1, teamAPlayer2, teamBPlayer1, teamBPlayer2
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
                // A casual game among friends often doesn't bother with
                // timeouts at all. On by default, but a one-tap opt-out
                // rather than a 0/1/2/3 count picker, which would be
                // clutter nobody but a tournament format actually needs.
                Toggle("Track Timeouts", isOn: $trackTimeouts)
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
                    .focused($focusedField, equals: .teamAPlayer1)
                    .accessibilityIdentifier("Team A Player Name")
                suggestionChips(for: $teamAPlayer1, selectedID: $teamAPlayer1ID, isFocused: focusedField == .teamAPlayer1)
                if playMode == .doubles {
                    TextField("Player 2", text: trackedTextBinding(text: $teamAPlayer2, selectedID: $teamAPlayer2ID))
                        .focused($focusedField, equals: .teamAPlayer2)
                        .accessibilityIdentifier("Team A Player 2 Name")
                    suggestionChips(for: $teamAPlayer2, selectedID: $teamAPlayer2ID, isFocused: focusedField == .teamAPlayer2)
                }
            }

            Section("Team B") {
                TextField(playMode == .doubles ? "Player 1" : "Player Name", text: trackedTextBinding(text: $teamBPlayer1, selectedID: $teamBPlayer1ID))
                    .focused($focusedField, equals: .teamBPlayer1)
                    .accessibilityIdentifier("Team B Player Name")
                suggestionChips(for: $teamBPlayer1, selectedID: $teamBPlayer1ID, isFocused: focusedField == .teamBPlayer1)
                if playMode == .doubles {
                    TextField("Player 2", text: trackedTextBinding(text: $teamBPlayer2, selectedID: $teamBPlayer2ID))
                        .focused($focusedField, equals: .teamBPlayer2)
                        .accessibilityIdentifier("Team B Player 2 Name")
                    suggestionChips(for: $teamBPlayer2, selectedID: $teamBPlayer2ID, isFocused: focusedField == .teamBPlayer2)
                }
                Button("Swap Teams") {
                    swapTeams()
                }
                .accessibilityIdentifier("Swap Teams")
                // "Swap Teams" only flips which side an existing pair is
                // on — it can't recombine players across pairs. This is
                // the one other degree of freedom that's missing: round-
                // robin doubles rotates partners, not just sides. Only
                // meaningful with two players per side, so doubles-only;
                // Player 1s stay put, only the Player 2s trade places.
                if playMode == .doubles {
                    Button("Swap Partners") {
                        swapPartners()
                    }
                    .accessibilityIdentifier("Swap Partners")
                }
            }

            Section {
                // Who serves first is decided on its own screen right
                // before scoring starts, not here — see `CoinFlipView`.
                // "Start Match" stages everything else and hands off to it.
                Button("Start Match") {
                    if activeMatchController.canStartNewMatch {
                        startMatch()
                    } else {
                        isShowingPaywall = true
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("Start Match")
            }
        }
        .navigationTitle("New Match")
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .onChange(of: pendingRematch) { _, newValue in
            guard let request = newValue else { return }
            applyRematch(request)
            onPrefillConsumed()
        }
        .onChange(of: pendingQuickStart) { _, newValue in
            guard let request = newValue else { return }
            applyQuickStart(request)
            onQuickStartConsumed()
        }
        .onAppear {
            // Covers the one case `.onChange` doesn't: a request that was
            // already set before this exact view instance was first created
            // (e.g. tapped "Rematch"/a Quick Start chip while a previous
            // match was still being scored, so this fresh MatchSetupView
            // only comes into existence once that match finishes and this
            // view appears for the first time already holding a non-nil
            // value — `.onChange` only fires on a value that CHANGES after
            // this view starts observing it).
            if let pendingRematch {
                applyRematch(pendingRematch)
                onPrefillConsumed()
            }
            if let pendingQuickStart {
                applyQuickStart(pendingQuickStart)
                onQuickStartConsumed()
            }
        }
    }

    private func applyRematch(_ request: RematchRequest) {
        playMode = request.configuration.playMode
        switch request.configuration.scoringFormat {
        case .sideOut:
            scoringFormatKind = .sideOut
            rallyFreeze = false
        case .rally(let freeze):
            scoringFormatKind = .rally
            rallyFreeze = freeze
        }
        winningScore = request.configuration.winningScore
        winByTwo = request.configuration.winByTwo
        trackTimeouts = request.configuration.timeoutsPerTeam > 0
        matchFormat = request.matchFormat
        teamAPlayer1 = request.teamAPlayer1.name
        teamAPlayer1ID = request.teamAPlayer1.savedPlayerID
        teamAPlayer2 = request.teamAPlayer2?.name ?? ""
        teamAPlayer2ID = request.teamAPlayer2?.savedPlayerID
        teamBPlayer1 = request.teamBPlayer1.name
        teamBPlayer1ID = request.teamBPlayer1.savedPlayerID
        teamBPlayer2 = request.teamBPlayer2?.name ?? ""
        teamBPlayer2ID = request.teamBPlayer2?.savedPlayerID
        // A rematch is a new match — the previous match's first-server
        // result must never carry over invisibly. Since who serves first is
        // now decided on its own screen after "Start Match" (see
        // `CoinFlipView`), there's nothing to reset here to force that —
        // every match, rematch or not, always goes through that screen.
    }

    private func swapTeams() {
        swap(&teamAPlayer1, &teamBPlayer1)
        swap(&teamAPlayer1ID, &teamBPlayer1ID)
        swap(&teamAPlayer2, &teamBPlayer2)
        swap(&teamAPlayer2ID, &teamBPlayer2ID)
    }

    /// Recombines pairs across teams (round-robin partner rotation) rather
    /// than moving a pair as a unit — Player 1s stay on their current
    /// side, only the Player 2s trade places.
    private func swapPartners() {
        swap(&teamAPlayer2, &teamBPlayer2)
        swap(&teamAPlayer2ID, &teamBPlayer2ID)
    }

    /// Fills slots in order (Team A Player 1, Team A Player 2, Team B
    /// Player 1, Team B Player 2) with whichever 1-4 players were selected
    /// on Home before navigating here — a single trip, not one per player.
    private func applyQuickStart(_ request: QuickStartRequest) {
        var remaining = request.players.prefix(4).map { $0 }
        if !remaining.isEmpty {
            let player = remaining.removeFirst()
            teamAPlayer1 = player.name
            teamAPlayer1ID = player.savedPlayerID
        }
        if !remaining.isEmpty {
            let player = remaining.removeFirst()
            teamAPlayer2 = player.name
            teamAPlayer2ID = player.savedPlayerID
        }
        if !remaining.isEmpty {
            let player = remaining.removeFirst()
            teamBPlayer1 = player.name
            teamBPlayer1ID = player.savedPlayerID
        }
        if !remaining.isEmpty {
            let player = remaining.removeFirst()
            teamBPlayer2 = player.name
            teamBPlayer2ID = player.savedPlayerID
        }
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
                // No-op guard: SwiftUI's TextField is not expected to echo
                // a programmatic write (a chip tap sets the raw $teamXPlayerN
                // binding directly, not this wrapper) back through its own
                // binding, but if some future TextField/OS behavior ever did,
                // this keeps that from silently clearing a just-set selectedID.
                guard newValue != text.wrappedValue else { return }
                text.wrappedValue = newValue
                selectedID.wrappedValue = nil
            }
        )
    }

    private func startMatch() {
        let scoringFormat: ScoringFormat = scoringFormatKind == .sideOut ? .sideOut : .rally(freeze: rallyFreeze)
        let configuration = GameConfiguration(
            playMode: playMode,
            scoringFormat: scoringFormat,
            winningScore: winningScore,
            winByTwo: winByTwo,
            timeoutsPerTeam: trackTimeouts ? winningScore.standardTimeoutsPerTeam : 0
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
        // Who serves first isn't decided yet — that happens on the
        // coin-flip screen `RootTabView` shows next, once this is staged.
        activeMatchController.stageMatch(PendingMatchSetup(
            configuration: configuration,
            matchFormat: matchFormat,
            teamAName: combinedName(teamAPlayer1, teamAPlayer2),
            teamBName: combinedName(teamBPlayer1, teamBPlayer2),
            teamAPlayerIDs: teamAPlayers.map(\.id),
            teamBPlayerIDs: teamBPlayers.map(\.id)
        ))
    }

    /// Shown while the field is focused (even empty, so tapping an empty
    /// field surfaces everyone ranked most-recently-played first — see
    /// `MatchRepository.suggestedPlayers`) or while it holds unselected
    /// typed text. Hidden the instant a chip is actually selected
    /// (`selectedID` non-nil) — otherwise the just-picked player's own
    /// chip would keep showing, since their name still matches itself.
    @ViewBuilder
    private func suggestionChips(for field: Binding<String>, selectedID: Binding<UUID?>, isFocused: Bool) -> some View {
        let query = field.wrappedValue
        if selectedID.wrappedValue == nil, isFocused || !query.isEmpty {
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
