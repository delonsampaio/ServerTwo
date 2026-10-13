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
        .onChange(of: activeMatchController.lastCanceledSetup) { _, newValue in
            guard let setup = newValue else { return }
            applyCancelRestore(setup)
            activeMatchController.clearLastCanceledSetup()
        }
        .onAppear {
            // Covers the one case `.onChange` doesn't: a request that was
            // already set before this exact view instance was first created
            // (e.g. tapped "Rematch"/a Quick Start chip while a previous
            // match was still being scored, so this fresh MatchSetupView
            // only comes into existence once that match finishes and this
            // view appears for the first time already holding a non-nil
            // value — `.onChange` only fires on a value that CHANGES after
            // this view starts observing it). This is actually the PRIMARY
            // path for a cancel restore, not just a fallback: canceling
            // always creates a fresh MatchSetupView synchronously (the
            // branch flips from ScoringView/CoinFlipView to it), so
            // `lastCanceledSetup` is already set by the time this instance
            // first appears, before `.onChange` above would ever see it
            // transition from nil.
            if let pendingRematch {
                applyRematch(pendingRematch)
                onPrefillConsumed()
            }
            if let pendingQuickStart {
                applyQuickStart(pendingQuickStart)
                onQuickStartConsumed()
            }
            if let setup = activeMatchController.lastCanceledSetup {
                applyCancelRestore(setup)
                activeMatchController.clearLastCanceledSetup()
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

        // A match saved before player-linking existed (or any save path
        // that didn't link players) carries no `savedPlayerID` for its
        // slots. Leaving those nil here would make Setup treat the
        // Rematch-prefilled name exactly like fresh, unselected typing —
        // showing suggestion chips under text the app itself just filled
        // in. Resolving an id up front (reusing an existing SavedPlayer by
        // name, or creating one) closes that gap instead of waiting for
        // Start Match to do the same upsert implicitly.
        let repository = MatchRepository(modelContext: modelContext)
        func resolvedID(name: String, existingID: UUID?) -> UUID? {
            if let existingID { return existingID }
            return try? repository.upsertSavedPlayer(name: name)?.id
        }
        teamAPlayer1 = request.teamAPlayer1.name
        teamAPlayer1ID = resolvedID(name: request.teamAPlayer1.name, existingID: request.teamAPlayer1.savedPlayerID)
        teamAPlayer2 = request.teamAPlayer2?.name ?? ""
        teamAPlayer2ID = request.teamAPlayer2.flatMap { resolvedID(name: $0.name, existingID: $0.savedPlayerID) }
        teamBPlayer1 = request.teamBPlayer1.name
        teamBPlayer1ID = resolvedID(name: request.teamBPlayer1.name, existingID: request.teamBPlayer1.savedPlayerID)
        teamBPlayer2 = request.teamBPlayer2?.name ?? ""
        teamBPlayer2ID = request.teamBPlayer2.flatMap { resolvedID(name: $0.name, existingID: $0.savedPlayerID) }
        // A rematch is a new match — the previous match's first-server
        // result must never carry over invisibly. Since who serves first is
        // now decided on its own screen after "Start Match" (see
        // `CoinFlipView`), there's nothing to reset here to force that —
        // every match, rematch or not, always goes through that screen.
    }

    /// `PendingMatchSetup` (unlike `RematchRequest`) only carries player
    /// ids, not names — at staging time there was no need to remember
    /// names separately, since `MatchSetupView` already had them in its
    /// own text fields. Restoring after a cancel has to look names back
    /// up from the ids instead.
    private func applyCancelRestore(_ setup: PendingMatchSetup) {
        playMode = setup.configuration.playMode
        switch setup.configuration.scoringFormat {
        case .sideOut:
            scoringFormatKind = .sideOut
            rallyFreeze = false
        case .rally(let freeze):
            scoringFormatKind = .rally
            rallyFreeze = freeze
        }
        winningScore = setup.configuration.winningScore
        winByTwo = setup.configuration.winByTwo
        trackTimeouts = setup.configuration.timeoutsPerTeam > 0
        matchFormat = setup.matchFormat

        let repository = MatchRepository(modelContext: modelContext)
        let allPlayers = (try? repository.fetchAllSavedPlayers()) ?? []
        func name(for id: UUID) -> String {
            allPlayers.first { $0.id == id }?.name ?? ""
        }

        teamAPlayer1ID = setup.teamAPlayerIDs.first
        teamAPlayer1 = teamAPlayer1ID.map(name) ?? ""
        teamAPlayer2ID = setup.teamAPlayerIDs.count > 1 ? setup.teamAPlayerIDs[1] : nil
        teamAPlayer2 = teamAPlayer2ID.map(name) ?? ""
        teamBPlayer1ID = setup.teamBPlayerIDs.first
        teamBPlayer1 = teamBPlayer1ID.map(name) ?? ""
        teamBPlayer2ID = setup.teamBPlayerIDs.count > 1 ? setup.teamBPlayerIDs[1] : nil
        teamBPlayer2 = teamBPlayer2ID.map(name) ?? ""
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

    /// Distributes whichever 1-4 players were selected on Home across
    /// teams and sides — a single trip to Setup, not one per player. The
    /// distribution (not just a sequential slot fill) and mode switch both
    /// matter: for exactly 2 players, the obvious intent is "these two are
    /// playing each other" (singles, one per side), not "these two are my
    /// doubles partners" — stacking both onto Team A would leave Team B
    /// empty and the match still in whatever mode Setup happened to be in.
    private func applyQuickStart(_ request: QuickStartRequest) {
        let players = Array(request.players.prefix(4))
        switch players.count {
        case 1:
            teamAPlayer1 = players[0].name
            teamAPlayer1ID = players[0].savedPlayerID
        case 2:
            playMode = .singles
            teamAPlayer1 = players[0].name
            teamAPlayer1ID = players[0].savedPlayerID
            teamBPlayer1 = players[1].name
            teamBPlayer1ID = players[1].savedPlayerID
        case 3:
            playMode = .doubles
            teamAPlayer1 = players[0].name
            teamAPlayer1ID = players[0].savedPlayerID
            teamAPlayer2 = players[1].name
            teamAPlayer2ID = players[1].savedPlayerID
            teamBPlayer1 = players[2].name
            teamBPlayer1ID = players[2].savedPlayerID
        case 4:
            playMode = .doubles
            teamAPlayer1 = players[0].name
            teamAPlayer1ID = players[0].savedPlayerID
            teamAPlayer2 = players[1].name
            teamAPlayer2ID = players[1].savedPlayerID
            teamBPlayer1 = players[2].name
            teamBPlayer1ID = players[2].savedPlayerID
            teamBPlayer2 = players[3].name
            teamBPlayer2ID = players[3].savedPlayerID
        default:
            break
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
                            Button {
                                field.wrappedValue = player.name
                                selectedID.wrappedValue = player.id
                            } label: {
                                HStack(spacing: 6) {
                                    PlayerAvatarView(player: player, size: 20)
                                    Text(player.name)
                                }
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
