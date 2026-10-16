import SwiftUI
import SwiftData
import PickleballKit
import UIKit

/// Digits only, max 2 characters — guards against pasted non-numeric input
/// slipping past .keyboardType(.numberPad), and against runaway length. No
/// real pickleball score needs 3+ digits.
fileprivate func quickLogSanitizedScoreText(_ text: String) -> String {
    String(text.filter(\.isNumber).prefix(2))
}

fileprivate struct QuickLogGameEntry: Identifiable {
    let id: Int  // 1-based game number — stable for the life of the sheet
    var teamAText: String = ""
    var teamBText: String = ""
}

/// Quick Log row state: which scores have been committed (validated, not
/// just typed) so far, whether the match is decided, and which rows should
/// be visible. It is a plain value type with no UIKit/SwiftUI dependencies,
/// but it is `fileprivate` and has no unit tests of its own — it is
/// exercised only through the UI tests. This type has no idea when
/// it's safe to call `commit()` — that discipline (immediately for
/// unambiguous edits, after a short debounce for an ambiguous single
/// digit, never on a stale mid-keystroke value) lives entirely in
/// MatchSetupView's wiring below, not here. See
/// QuickLogRowVisibilityUITests for the test that actually verifies that
/// wiring discipline — a unit test of this type alone cannot, since
/// `commit()` has no way to distinguish "the user finished typing this
/// score" from "the user is mid-keystroke."
fileprivate struct QuickLogState {
    private(set) var entries: [QuickLogGameEntry]
    private(set) var committedScores: [(teamA: Int, teamB: Int)] = []
    private(set) var isDecided = false
    private let matchFormat: MatchFormat
    private let configuration: GameConfiguration

    init(matchFormat: MatchFormat, configuration: GameConfiguration) {
        self.matchFormat = matchFormat
        self.configuration = configuration
        // Rows up to (matchFormat.gamesToWin * 2) - 1 — the most games
        // that format could ever need (1 for Best of 1, 3 for Best of 3,
        // 5 for Best of 5).
        self.entries = (1...((matchFormat.gamesToWin * 2) - 1)).map { QuickLogGameEntry(id: $0) }
    }

    /// Visible up to the point the match is decided (then no further
    /// rows) or one past the last committed-and-valid row (the next one
    /// to fill in) — a pure function of committedScores, never a
    /// destructive mutation of entries itself. A row that becomes hidden
    /// keeps its typed text untouched underneath.
    var visibleEntries: [QuickLogGameEntry] {
        let visibleCount = isDecided
            ? committedScores.count
            : min(committedScores.count + 1, entries.count)
        return Array(entries.prefix(visibleCount))
    }

    mutating func updateText(gameID: Int, team: Team, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == gameID }) else { return }
        if team == .teamA {
            entries[index].teamAText = text
        } else {
            entries[index].teamBText = text
        }
    }

    /// Re-derives committedScores/isDecided from entries' CURRENT text.
    /// Stops at the first row that isn't both parseable and a legal
    /// completed game under the current rules, or once a team has
    /// already reached matchFormat.gamesToWin — later rows (even with
    /// typed text) never contribute, but their text is untouched either
    /// way.
    mutating func commit() {
        var scores: [(teamA: Int, teamB: Int)] = []
        var gamesWon: [Team: Int] = [.teamA: 0, .teamB: 0]
        for entry in entries {
            guard gamesWon[.teamA, default: 0] < matchFormat.gamesToWin,
                  gamesWon[.teamB, default: 0] < matchFormat.gamesToWin else { break }
            guard let teamA = Int(entry.teamAText.trimmingCharacters(in: .whitespaces)),
                  let teamB = Int(entry.teamBText.trimmingCharacters(in: .whitespaces)),
                  configuration.isCompletedGameScore(teamA: teamA, teamB: teamB) else { break }
            let winner: Team = teamA > teamB ? .teamA : .teamB
            gamesWon[winner, default: 0] += 1
            scores.append((teamA: teamA, teamB: teamB))
        }
        committedScores = scores
        isDecided = gamesWon[.teamA, default: 0] >= matchFormat.gamesToWin
            || gamesWon[.teamB, default: 0] >= matchFormat.gamesToWin
    }
}

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
    @State private var isShowingQuickLog = false
    @State private var quickLogState: QuickLogState?
    // One shared debounce task for the whole sheet, not one per row/field
    // — a new edit anywhere cancels and replaces whatever's pending, so
    // rapid cross-field edits (e.g. an external keyboard tabbing between
    // fields) are handled correctly by a single, always-current task.
    @State private var quickLogCommitTask: Task<Void, Never>?
    @State private var quickLogSaveErrorMessage: String?

    /// How long an ambiguous single digit waits before committing. 350ms in
    /// release; debug builds let UI tests widen/narrow it with
    /// `-UITest-QuickLogDebounceMs <int>` (same debug-only launch-argument
    /// style as `-UITest-DemoMatchLimit` in MyApp), so timing-sensitive
    /// assertions don't depend on simulator speed.
    private static let quickLogDebounce: Duration = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-UITest-QuickLogDebounceMs"),
           index + 1 < arguments.count,
           let milliseconds = Int(arguments[index + 1]) {
            return .milliseconds(milliseconds)
        }
        #endif
        return .milliseconds(350)
    }()

    private enum ScoringFormatKind: String, CaseIterable, Identifiable {
        case sideOut = "Side-Out"
        case rally = "Rally"
        var id: String { rawValue }
    }

    private enum NameField: Hashable {
        case teamAPlayer1, teamAPlayer2, teamBPlayer1, teamBPlayer2
    }

    var body: some View {
        // "Start Match" lives outside the Form, pinned above the tab bar
        // (matching "New Match" on Home) — inside the scrolling Form, a
        // user who lands here via Rematch/Quick Start (or just typed two
        // names) still had to scroll past the whole "Match Rules" card
        // every time to reach it, even though the rules usually stay on
        // their defaults.
        VStack(spacing: 0) {
            Form {
            // Players change on nearly every match; rules mostly stay on
            // their defaults. Team A/B sit right under Mode (which
            // controls how many player fields each shows) so entering
            // players never needs scrolling past four static rules
            // sections first — the rules themselves are still here, just
            // consolidated into one card below instead of four.
            Section("Mode") {
                Picker("Mode", selection: $playMode) {
                    Text("Singles").tag(PlayMode.singles)
                    Text("Doubles").tag(PlayMode.doubles)
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

            Section {
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
            } header: {
                // Both swap actions moved into Team B's own header
                // (trailing side) instead of being rows inside Team B's
                // card — as body rows they made Team B's card visibly
                // taller than Team A's (an asymmetry neither swap
                // actually implies) and made each read as something that
                // belonged to Team B specifically, when both are really
                // actions on the pairing between the two teams.
                HStack {
                    Text("Team B")
                    Spacer()
                    HStack(spacing: 14) {
                        // "Swap Teams" only flips which side an existing
                        // pair is on — it can't recombine players across
                        // pairs. "Swap Partners" is the one other degree
                        // of freedom that's missing: round-robin doubles
                        // rotates partners, not just sides. Only
                        // meaningful with two players per side, so
                        // doubles-only; Player 1s stay put, only the
                        // Player 2s trade places.
                        if playMode == .doubles {
                            Button {
                                swapPartners()
                            } label: {
                                Label("Swap Partners", systemImage: "arrow.left.arrow.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .accessibilityIdentifier("Swap Partners")
                        }
                        Button {
                            swapTeams()
                        } label: {
                            Label("Swap Teams", systemImage: "arrow.up.arrow.down")
                                .font(.caption.weight(.semibold))
                        }
                        .accessibilityIdentifier("Swap Teams")
                    }
                }
            }

            Section("Match Rules") {
                // Segmented (not the Form-default drill-down row) —
                // unchanged from before consolidation, just relocated.
                Picker("Scoring", selection: $scoringFormatKind) {
                    ForEach(ScoringFormatKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                if scoringFormatKind == .rally {
                    Toggle("Win game point on serve only (freeze)", isOn: $rallyFreeze)
                }
                Picker("Format", selection: $matchFormat) {
                    ForEach(MatchFormat.allCases, id: \.self) { format in
                        Text("Best of \(format.rawValue)").tag(format)
                    }
                }
                .pickerStyle(.segmented)
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
            }

            // Who serves first is decided on its own screen right before
            // scoring starts, not here — see `CoinFlipView`. "Start
            // Match" stages everything else and hands off to it. Styled
            // and placed the same way as "New Match" on Home: a bold,
            // full-width primary CTA pinned outside the scrolling
            // content, not a row at the bottom of it. `.glassProminent`
            // (not a hand-drawn accent-color fill) so it renders as true
            // Liquid Glass material instead of a flat rectangle.
            Button {
                if activeMatchController.canStartNewMatch {
                    startMatch()
                } else {
                    isShowingPaywall = true
                }
            } label: {
                Text("Start Match")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.accentColor)
            .controlSize(.large)
            .padding()
            .accessibilityIdentifier("Start Match")

            // Visually secondary (a plain text button, not competing with
            // the pinned CTA above it) — same relationship "Already spun a
            // paddle?" has to the main flow on CoinFlipView. Gated by the
            // same canStartNewMatch check as "Start Match," so Quick Log
            // can't become an unlimited free-tier loophole around the
            // demo-match paywall.
            Button {
                if activeMatchController.canStartNewMatch {
                    presentQuickLogSheet()
                } else {
                    isShowingPaywall = true
                }
            } label: {
                Text("Log Final Score Instead")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.bottom, 4)
            .accessibilityIdentifier("Log Final Score Instead")
        }
        .navigationTitle("New Match")
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        // The capture list makes `body` itself read `quickLogState`, so
        // SwiftUI re-evaluates `body` (and re-captures this closure)
        // whenever it changes. Without it, `body` only touches the
        // `$isShowingQuickLog` binding (which creates no dependency), and
        // the sheet presents with a closure captured before
        // `presentQuickLogSheet()` set the state — an empty sheet.
        // `onDismiss` clears focus AFTER dismissal completes — SwiftUI
        // restores the parent's last-focused name field during dismissal,
        // so clearing earlier (in `resetSetupFields()`) loses the race and
        // the keyboard returns over the reset form.
        .sheet(isPresented: $isShowingQuickLog, onDismiss: { focusedField = nil }) { [quickLogState] in
            quickLogSheet(quickLogState)
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

    /// Prefers the exact SavedPlayer the user selected via a suggestion
    /// chip (re-verified against the current text, in case anything
    /// slipped past `trackedTextBinding`'s invalidation) over a fresh
    /// name-based upsert — this is what correctly disambiguates two
    /// different SavedPlayers that happen to share a name (the "Two
    /// Mikes" case), instead of an arbitrary name lookup. Shared by
    /// `startMatch()` and `saveQuickLoggedMatch()` — both resolve players
    /// from the same typed name fields the same way.
    private func resolvedPlayer(name: String, selectedID: UUID?) -> SavedPlayer? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = MatchRepository(modelContext: modelContext)
        if let selectedID,
           let existing = try? repository.fetchAllSavedPlayers().first(where: { $0.id == selectedID }),
           existing.name.caseInsensitiveCompare(trimmed) == .orderedSame {
            return existing
        }
        return try? repository.upsertSavedPlayer(name: name)
    }

    private func resolvedPlayers(_ pairs: (String, UUID?)...) -> [SavedPlayer] {
        // Dedupe by id: a doubles side with the same name typed into both
        // fields must not double-count that one player in
        // `timesPlayed`/stats attribution.
        var seen = Set<UUID>()
        return pairs.compactMap { resolvedPlayer(name: $0.0, selectedID: $0.1) }
            .filter { seen.insert($0.id).inserted }
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

    private var quickLogConfiguration: GameConfiguration {
        GameConfiguration(
            playMode: playMode,
            scoringFormat: scoringFormatKind == .sideOut ? .sideOut : .rally(freeze: rallyFreeze),
            winningScore: winningScore,
            winByTwo: winByTwo,
            timeoutsPerTeam: trackTimeouts ? winningScore.standardTimeoutsPerTeam : 0
        )
    }

    private var quickLogTeamAName: String {
        let name = combinedName(teamAPlayer1, teamAPlayer2)
        return name.isEmpty ? "Team A" : name
    }

    private var quickLogTeamBName: String {
        let name = combinedName(teamBPlayer1, teamBPlayer2)
        return name.isEmpty ? "Team B" : name
    }

    private func presentQuickLogSheet() {
        quickLogState = QuickLogState(matchFormat: matchFormat, configuration: quickLogConfiguration)
        isShowingQuickLog = true
    }

    private func commitQuickLogRow() {
        quickLogState?.commit()
    }

    /// `quickLogState.entries` isn't addressable through a normal index
    /// `Binding` the way a plain `@State` array is, since `quickLogState`
    /// itself is wrapped in an `Optional`. This wraps lookup-by-id (not
    /// index) into an ordinary `Binding<String>`, reading/writing through
    /// `quickLogState?.updateText` — every keystroke still writes straight
    /// into `entries` immediately (never deferred), which is what keeps a
    /// row's typed text intact even while the row is temporarily hidden.
    /// `set` also classifies and schedules the commit — see
    /// `scheduleQuickLogCommit` below.
    private func quickLogScoreBinding(gameID: Int, team: Team) -> Binding<String> {
        Binding(
            get: {
                guard let entry = quickLogState?.entries.first(where: { $0.id == gameID }) else { return "" }
                return team == .teamA ? entry.teamAText : entry.teamBText
            },
            set: { newValue in
                // The raw text is stored as-is (even if it needs trimming)
                // so the state really changes and the TextField is pushed
                // the trimmed value by `QuickLogRow`'s `.onChange`
                // normalization below. Storing the sanitized text here
                // instead left the stored value unchanged when a 3rd digit
                // was typed after "13", so the field kept DISPLAYING
                // "135" while the state held "13". A commit is scheduled
                // only for already-sanitized text — the normalization's own
                // write re-enters this setter with the trimmed value.
                quickLogState?.updateText(gameID: gameID, team: team, text: newValue)
                if newValue == quickLogSanitizedScoreText(newValue) {
                    scheduleQuickLogCommit(gameID: gameID, team: team)
                }
            }
        )
    }

    /// Classifies the just-edited field and either commits immediately or
    /// after a short debounce. A field only waits when its OWN text is a
    /// single digit 1-9 that some further digit could extend into a
    /// different, independently-valid outcome; everything else (blank,
    /// invalid, multi-digit, or an unextendable single digit) commits at
    /// once. Driven purely by text-binding changes — deliberately not by
    /// `@FocusState`: an earlier @FocusState-based commit trigger was
    /// observed unreliable here (possibly the stale sheet-closure capture
    /// rather than FocusState itself); this text-driven design doesn't
    /// depend on focus.
    private func scheduleQuickLogCommit(gameID: Int, team: Team) {
        quickLogCommitTask?.cancel()
        guard let entry = quickLogState?.entries.first(where: { $0.id == gameID }) else { return }
        let text = team == .teamA ? entry.teamAText : entry.teamBText
        let otherText = team == .teamA ? entry.teamBText : entry.teamAText

        if let otherScore = Int(otherText.trimmingCharacters(in: .whitespaces)),
           isAmbiguousSingleDigit(text, otherScore: otherScore, configuration: quickLogConfiguration) {
            quickLogCommitTask = Task { @MainActor in
                try? await Task.sleep(for: Self.quickLogDebounce)
                guard !Task.isCancelled else { return }
                commitQuickLogRow()
            }
        } else {
            commitQuickLogRow()
        }
    }

    /// True only when `text` is a single digit 1-9 that some further
    /// digit (0-9) could extend into a legal completed game score —
    /// checked with `text` as either side's score, since either team
    /// could end up the winner. `11` and otherScore `1` is ambiguous this
    /// way (11-1 and 11-13 are both independently valid, different
    /// winners); `11` and otherScore `9` is not (no digit appended to "9"
    /// can produce a valid score against 11, so 11-9 commits immediately).
    private func isAmbiguousSingleDigit(_ text: String, otherScore: Int, configuration: GameConfiguration) -> Bool {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value > 0, value < 10 else { return false }
        return (0...9).contains { digit in
            let candidate = value * 10 + digit
            return configuration.isCompletedGameScore(teamA: candidate, teamB: otherScore)
                || configuration.isCompletedGameScore(teamA: otherScore, teamB: candidate)
        }
    }

    private func quickLogSheet(_ state: QuickLogState?) -> some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(quickLogTeamAName)
                        Spacer()
                        Text(quickLogTeamBName)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                Section("Game Scores") {
                    ForEach(state?.visibleEntries ?? []) { entry in
                        QuickLogRow(
                            gameID: entry.id,
                            teamAText: quickLogScoreBinding(gameID: entry.id, team: .teamA),
                            teamBText: quickLogScoreBinding(gameID: entry.id, team: .teamB)
                        )
                    }
                }
            }
            .navigationTitle("Log Final Score")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        quickLogCommitTask?.cancel()
                        isShowingQuickLog = false
                    }
                    .accessibilityIdentifier("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveQuickLoggedMatch() }
                        .disabled(!(state?.isDecided ?? false))
                        .accessibilityIdentifier("Save")
                }
                // .numberPad has no Return key, so this is the only way to
                // dismiss the keyboard — Save/row-reveal don't depend on
                // this being tapped, but there's still no other way to put
                // the keyboard away.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        quickLogCommitTask?.cancel()
                        commitQuickLogRow()
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityIdentifier("QuickLog.Done")
                }
            }
        }
        // Attached inside the sheet content: the sheet is its own
        // presentation context, so an alert on the parent view wouldn't
        // appear over it.
        .alert("Save Failed", isPresented: Binding(
            get: { quickLogSaveErrorMessage != nil },
            set: { isPresented in if !isPresented { quickLogSaveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(quickLogSaveErrorMessage ?? "")
        }
        .presentationDetents([.medium, .large])
    }

    private func saveQuickLoggedMatch() {
        // Defensive re-commit: cancels any pending debounced commit (up to
        // ~350ms away, e.g. the user just backspaced "13" to "1") so it
        // can't fire against the sheet after this save has already
        // consumed the state, then re-derives isDecided fresh right before
        // using it — Save either acts on genuinely-current data or safely
        // no-ops, never on stale data.
        quickLogCommitTask?.cancel()
        quickLogState?.commit()
        guard let state = quickLogState, state.isDecided else { return }

        let teamAPlayers = playMode == .doubles
            ? resolvedPlayers((teamAPlayer1, teamAPlayer1ID), (teamAPlayer2, teamAPlayer2ID))
            : resolvedPlayers((teamAPlayer1, teamAPlayer1ID))
        let teamBPlayers = playMode == .doubles
            ? resolvedPlayers((teamBPlayer1, teamBPlayer1ID), (teamBPlayer2, teamBPlayer2ID))
            : resolvedPlayers((teamBPlayer1, teamBPlayer1ID))
        let repository = MatchRepository(modelContext: modelContext)
        // A failed save must not look like success: keep the sheet open and
        // the typed scores intact so the user can retry (mirrors the Finish
        // Match "Save Failed" alert in ScoringView).
        do {
            _ = try repository.saveQuickLoggedMatch(
                configuration: quickLogConfiguration,
                matchFormat: matchFormat,
                teamAName: quickLogTeamAName,
                teamBName: quickLogTeamBName,
                gameScores: state.committedScores,
                teamAPlayers: teamAPlayers,
                teamBPlayers: teamBPlayers
            )
            isShowingQuickLog = false
            resetSetupFields()
        } catch {
            // Discard the failed save's pending inserts (match/sides/games) so
            // a retry doesn't duplicate them. Upserted SavedPlayers are
            // already persisted by their own save, so they survive this.
            modelContext.rollback()
            quickLogSaveErrorMessage = "Couldn't save this match. Please try again."
        }
    }

    /// Mirrors what finishing a *live* match does for free today —
    /// RootTabView tears down and rebuilds MatchSetupView when it switches
    /// back to it after finishMatch(), which is what naturally clears its
    /// fields. Quick Log's sheet never leaves this view (no live match is
    /// ever created), so there's no teardown to rely on — this makes that
    /// reset explicit instead.
    private func resetSetupFields() {
        teamAPlayer1 = ""
        teamAPlayer1ID = nil
        teamAPlayer2 = ""
        teamAPlayer2ID = nil
        teamBPlayer1 = ""
        teamBPlayer1ID = nil
        teamBPlayer2 = ""
        teamBPlayer2ID = nil
    }
}

/// Takes its two fields' text as plain Bindings — no focus tracking at
/// all, since commit timing is driven entirely by each field's text
/// changes (an earlier @FocusState-based commit trigger was observed
/// unreliable here — possibly the stale sheet-closure capture rather than
/// FocusState itself — so this text-driven design doesn't depend on focus).
fileprivate struct QuickLogRow: View {
    let gameID: Int
    @Binding var teamAText: String
    @Binding var teamBText: String

    var body: some View {
        HStack {
            Text("Game \(gameID)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            TextField("0", text: $teamAText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .onChange(of: teamAText) { _, newValue in
                    let sanitized = quickLogSanitizedScoreText(newValue)
                    if sanitized != newValue { teamAText = sanitized }
                }
                .accessibilityIdentifier("QuickLog.Game\(gameID).TeamAScore")
            Text("–")
                .foregroundStyle(.secondary)
            TextField("0", text: $teamBText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .onChange(of: teamBText) { _, newValue in
                    let sanitized = quickLogSanitizedScoreText(newValue)
                    if sanitized != newValue { teamBText = sanitized }
                }
                .accessibilityIdentifier("QuickLog.Game\(gameID).TeamBScore")
        }
    }
}
