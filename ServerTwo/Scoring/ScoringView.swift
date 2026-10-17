import SwiftUI
import PickleballKit

struct ScoringView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    @Environment(AppSettings.self) private var appSettings

    @State private var isShowingScoreCorrection = false
    @State private var sideSwitchAcknowledgedForGameIndex = -1
    @State private var sideSwitchAcknowledgedViaCorrectionForGameIndex = -1
    @State private var gameOverAcknowledgedForGameIndex = -1
    @State private var showingFinishConfirmation = false
    @State private var finishErrorMessage: String?
    // SwiftUI can present only one sheet from a view at a time and silently
    // drops or clobbers the second. Game Over / Side Switch usually fire while
    // the Correct Score sheet is still on screen (the correction commits, then
    // dismisses), so prompts are queued FIFO and only shown once no other
    // sheet is up (see `presentNextPromptIfPossible`).
    @State private var prompt: ScoringPrompt?
    @State private var pendingPrompts: [ScoringPrompt] = []

    var body: some View {
        Group {
            if let match = activeMatchController.match {
                content(for: match)
            } else {
                ContentUnavailableView("No Active Match", systemImage: "sportscourt")
            }
        }
        .navigationTitle("\(activeMatchController.teamAName) vs \(activeMatchController.teamBName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The only way out of a match before finishing it — ScoringView
            // is the root of the Play tab's content while a match is live,
            // not pushed via NavigationLink, so there's no back button to
            // fall back on otherwise.
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel Match", role: .destructive) {
                    if let match = activeMatchController.match {
                        enqueue(.cancelMatch(
                            teamAName: activeMatchController.teamAName,
                            teamBName: activeMatchController.teamBName,
                            teamAScore: match.currentGame.state.teamAScore,
                            teamBScore: match.currentGame.state.teamBScore,
                            teamAGames: match.gamesWon(for: .teamA),
                            teamBGames: match.gamesWon(for: .teamB),
                            completedGameCount: match.completedGames.count
                        ))
                    }
                }
                .accessibilityIdentifier("Cancel Match")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeMatchController.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
                .accessibilityLabel("Undo")
            }
        }
        .sheet(isPresented: $isShowingScoreCorrection, onDismiss: {
            // The side-switch check has a same-transaction presentation race:
            // `PickleballGame.correctScores` also calls `checkSideSwitch()`, so a
            // correction that crosses the threshold flips `hasSideSwitched`
            // inside the sheet's `onCommit`, immediately before its own
            // `dismiss()`. The `.onChange(of: ...hasSideSwitched)` handler below
            // is kept as-is for the `recordPoint` path (which has no such race);
            // this is an ADDITIONAL, race-free trigger for the correction-sheet
            // path only. It uses its OWN tracking variable, not the onChange
            // handler's — `onChange` fires as part of the same transaction that
            // triggers this race (before `onDismiss` runs), so if it shared the
            // guard, it would already have consumed it by the time this check
            // runs, defeating the fallback in exactly the scenario it exists
            // for. A separate variable means this check still fires even when
            // the onChange handler's own prompt silently failed to present.
            if let match = activeMatchController.match {
                let gameIndex = match.completedGames.count
                if match.currentGame.state.hasSideSwitched, !match.isMatchOver, sideSwitchAcknowledgedViaCorrectionForGameIndex != gameIndex {
                    sideSwitchAcknowledgedViaCorrectionForGameIndex = gameIndex
                    sideSwitchAcknowledgedForGameIndex = gameIndex
                    // Queued prompts don't race the dismissal, so the onChange
                    // handler's own enqueue (made while this sheet was still
                    // up) is waiting in the queue; adding a second one here
                    // would show the same side switch twice.
                    if !pendingPrompts.contains(where: { $0.id == "sideSwitch" }), prompt?.id != "sideSwitch" {
                        enqueue(sideSwitchPrompt(for: match))
                    }
                }
            }
            presentNextPromptIfPossible()
        }) {
            if let match = activeMatchController.match {
                ScoreCorrectionSheet(
                    teamAName: activeMatchController.teamAName,
                    teamBName: activeMatchController.teamBName,
                    currentTeamAScore: match.currentGame.state.teamAScore,
                    currentTeamBScore: match.currentGame.state.teamBScore,
                    configuration: match.configuration,
                    onCommit: { teamA, teamB in
                        activeMatchController.correctScores(teamA: teamA, teamB: teamB)
                    }
                )
            }
        }
        .onChange(of: activeMatchController.match.map(ObjectIdentifier.init)) { _, _ in
            // A new match (including a fresh one right after finishing the
            // previous one) must re-arm the side-switch prompt — without this,
            // acknowledging the side switch in one match can suppress the
            // prompt for every subsequent match's first side switch, since
            // completedGames.count restarts at 0 each time and would otherwise
            // collide with a previously-acknowledged index. Queued/visible
            // prompts belong to the old match too (e.g. a cancelled one).
            prompt = nil
            pendingPrompts = []
            sideSwitchAcknowledgedForGameIndex = -1
            sideSwitchAcknowledgedViaCorrectionForGameIndex = -1
            gameOverAcknowledgedForGameIndex = -1
        }
        .onChange(of: activeMatchController.match?.completedGames.count) { _, newCount in
            // A completed game that doesn't end the match silently resets the
            // visible point score to 0-0. Without feedback that reads as lost
            // data, so acknowledge each newly-completed game once. The tracking
            // var holds the INDEX of the game already acknowledged, and game
            // index i completes when completedGames.count becomes i + 1 — hence
            // the `+ 1` on both sides.
            guard let match = activeMatchController.match, let newCount else { return }
            guard newCount > gameOverAcknowledgedForGameIndex + 1, !match.isMatchOver else { return }
            gameOverAcknowledgedForGameIndex = newCount - 1
            // `completedGames.last` is the game just finished; the prompt
            // carries its own final score because the live score has already
            // reset to 0-0 for the next game.
            if let finishedGame = match.completedGames.last {
                enqueue(.gameOver(
                    gameNumber: newCount,
                    teamAName: activeMatchController.teamAName,
                    teamBName: activeMatchController.teamBName,
                    teamAScore: finishedGame.state.teamAScore,
                    teamBScore: finishedGame.state.teamBScore,
                    winner: finishedGame.gameWinner,
                    teamAGames: match.gamesWon(for: .teamA),
                    teamBGames: match.gamesWon(for: .teamB)
                ))
            }
        }
        .onChange(of: activeMatchController.match?.currentGame.state.hasSideSwitched) { _, hasSideSwitched in
            guard let match = activeMatchController.match else { return }
            let gameIndex = match.completedGames.count
            if hasSideSwitched == true, !match.isMatchOver, sideSwitchAcknowledgedForGameIndex != gameIndex {
                sideSwitchAcknowledgedForGameIndex = gameIndex
                enqueue(sideSwitchPrompt(for: match))
            }
        }
        .sheet(item: $prompt, onDismiss: { presentNextPromptIfPossible() }) { item in
            ScoringPromptSheet(prompt: item, onCancelMatch: {
                activeMatchController.cancelActiveMatch()
            })
        }
        .alert("Save Failed", isPresented: Binding(
            get: { finishErrorMessage != nil },
            set: { isPresented in if !isPresented { finishErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(finishErrorMessage ?? "")
        }
        .sheet(isPresented: $showingFinishConfirmation, onDismiss: { presentNextPromptIfPossible() }) {
            if let match = activeMatchController.match, let winningTeam = match.matchWinner {
                FinishMatchSheet(
                    teamAName: activeMatchController.teamAName,
                    teamBName: activeMatchController.teamBName,
                    isBestOfOne: match.matchFormat == .bestOfOne,
                    teamAScore: match.currentGame.state.teamAScore,
                    teamBScore: match.currentGame.state.teamBScore,
                    teamAGames: match.gamesWon(for: .teamA),
                    teamBGames: match.gamesWon(for: .teamB),
                    winningTeam: winningTeam,
                    onConfirm: {
                        // A save failure used to be swallowed by `try?`, leaving
                        // the user stuck on a finished match with no feedback at
                        // all.
                        do {
                            try activeMatchController.finishMatch()
                        } catch {
                            finishErrorMessage = "Couldn't save this match. Please try again."
                        }
                    }
                )
            }
        }
    }

    private func sideSwitchPrompt(for match: PickleballMatch) -> ScoringPrompt {
        .sideSwitch(
            teamAName: activeMatchController.teamAName,
            teamBName: activeMatchController.teamBName,
            teamAScore: match.currentGame.state.teamAScore,
            teamBScore: match.currentGame.state.teamBScore
        )
    }

    private func enqueue(_ newPrompt: ScoringPrompt) {
        pendingPrompts.append(newPrompt)
        presentNextPromptIfPossible()
    }

    /// Shows the next queued prompt unless something is already on screen.
    /// Called after every enqueue and whenever a sheet this view owns is
    /// dismissed, so a prompt that had to wait appears right after the sheet
    /// that blocked it.
    private func presentNextPromptIfPossible() {
        guard prompt == nil, !isShowingScoreCorrection, !showingFinishConfirmation,
              !pendingPrompts.isEmpty else { return }
        prompt = pendingPrompts.removeFirst()
    }

    private var canUndo: Bool {
        guard let match = activeMatchController.match else { return false }
        return match.currentGame.canUndo || !match.completedGames.isEmpty
    }

    @ViewBuilder
    private func content(for match: PickleballMatch) -> some View {
        VStack(spacing: 16) {
            // Without this, a best-of-3/5 match never shows the match score at
            // all: winning a game resets the visible point score to 0-0 with no
            // indication that a game was banked.
            if match.matchFormat != .bestOfOne {
                Text("Games: \(match.gamesWon(for: .teamA)) – \(match.gamesWon(for: .teamB))")
                    .font(.title3.bold())
            }

            // Who's serving now lives inside each team's own score card
            // (a fixed-height badge slot at its top) instead of a separate
            // diagram floating above the cards, divorced from the
            // player/score it's actually about.
            HStack(spacing: 12) {
                scoreZone(for: .teamA, match: match)
                scoreZone(for: .teamB, match: match)
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity)

            // Hidden once the match is decided — there's no more play left to
            // pause, and showing them pushed the "Finish Match" button's
            // position around every time a match ended. isMatchOver is
            // computed live from the current score, so undoing the winning
            // point un-finishes the match and these reappear automatically.
            // Also hidden entirely (not just disabled) when the match was
            // set up with "Track Timeouts" off — two permanently-grayed-out
            // buttons would just be clutter for a casual game that was
            // explicitly opted out of tracking them.
            if !match.isMatchOver, match.configuration.timeoutsPerTeam > 0 {
                TimeoutControlsView(state: match.currentGame.state) { team in
                    activeMatchController.requestTimeout(for: team)
                }
                .padding(.horizontal)
            }

            if match.isMatchOver {
                Button("Finish Match") {
                    showingFinishConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .accessibilityIdentifier("Finish Match")
            }
        }
        .padding(.vertical)
    }

    private func scoreZone(for team: Team, match: PickleballMatch) -> some View {
        let name = team == .teamA ? activeMatchController.teamAName : activeMatchController.teamBName
        let score = match.currentGame.state.score(for: team)
        let isServing = match.currentGame.state.servingTeam == team
        return VStack(spacing: 8) {
            // A fixed-height slot whether or not this team is serving
            // — if the receiving side just left it empty with nothing
            // reserving the space, its card's content would sit lower
            // than the serving side's, breaking the side-by-side
            // alignment the two cards are supposed to share.
            Group {
                if isServing {
                    Label("SERVING", systemImage: "circle.grid.cross.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                } else {
                    Color.clear
                }
            }
            .frame(height: 28)

            Spacer()

            // Both sides stay full .primary contrast — the serving
            // card's border, tint, and badge already distinguish it,
            // and dimming the receiving side's score actively hurts
            // the courtside-glare legibility this screen is built
            // for (see the type above). Sizes pushed up (name to
            // .title, score to 108pt) to actually use the height
            // these full-height cards have to give.
            Text(name)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(score)")
                .font(.system(size: 108, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Text("Tap to Score")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isServing ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isServing ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isServing ? 2 : 1)
        )
        .contentShape(Rectangle())
        // Tap to score, hold to correct — decided from the touch's own timing
        // (see `TapOrHoldModifier`), NOT from SwiftUI's `.onTapGesture` +
        // `.onLongPressGesture` pair: that pair left a dead zone where a press
        // longer than a quick tap but shorter than the long-press duration did
        // nothing, silently dropping a point on a slightly slow tap (found on a
        // real device). A Button is out too: its own press handling beat an
        // outer long-press, so the correction sheet could never open. A hold
        // that opens the sheet never also scores when released.
        .modifier(TapOrHoldModifier(
            holdDuration: .milliseconds(500),
            onTap: {
                guard !match.isMatchOver else { return }
                activeMatchController.recordPoint(for: team)
            },
            onHold: {
                guard !match.isMatchOver else { return }
                isShowingScoreCorrection = true
            }
        ))
        // Spec §3.7 scopes haptics into this phase's ScoringView work. The
        // condition closure both respects the user's toggle and limits firing
        // to actual score increases, so an unrelated re-render or an undo
        // doesn't buzz.
        .sensoryFeedback(.impact, trigger: score) { oldValue, newValue in
            appSettings.hapticsEnabled && newValue > oldValue
        }
        .disabled(match.isMatchOver)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !match.isMatchOver else { return }
            activeMatchController.recordPoint(for: team)
        }
        .accessibilityAction(named: "Correct score") {
            guard !match.isMatchOver else { return }
            isShowingScoreCorrection = true
        }
        .accessibilityIdentifier("scoreZone.\(team.rawValue)")
        .accessibilityLabel("\(name), \(score) points. Tap to score, double tap and hold to correct.")
    }

}

/// Tap to score, hold to correct — decided from the touch's own timing so a
/// press of ANY length shorter than `holdDuration` is a tap. SwiftUI's
/// `.onTapGesture` + `.onLongPressGesture` pair left a dead zone: a press
/// longer than a quick tap but shorter than the long-press duration did
/// nothing, silently dropping points on a slightly slow tap.
private struct TapOrHoldModifier: ViewModifier {
    let holdDuration: Duration
    let onTap: () -> Void
    let onHold: () -> Void

    private enum Phase { case idle, pressing, holdFired }
    @State private var phase: Phase = .idle
    // Resets to false automatically when the touch ends OR is cancelled
    // (`DragGesture.Value` has no `startTime` to tell touches apart), so a
    // touch that never delivers `onEnded` can't leave the zone stuck.
    @GestureState private var touchActive = false
    @State private var holdTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .opacity(phase == .pressing ? 0.7 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touchActive) { _, state, _ in state = true }
                    .onChanged { _ in
                        // Only the first change of a touch starts a press.
                        guard phase == .idle else { return }
                        holdTask?.cancel()
                        phase = .pressing
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(for: holdDuration)
                            guard !Task.isCancelled, phase == .pressing else { return }
                            phase = .holdFired
                            onHold()
                        }
                    }
                    .onEnded { value in
                        holdTask?.cancel()
                        holdTask = nil
                        let wasPressing = phase == .pressing
                        phase = .idle
                        let moved = hypot(value.translation.width, value.translation.height) > 20
                        guard wasPressing, !moved else { return }
                        onTap()
                    }
            )
            .onChange(of: touchActive) { _, active in
                // Touch cancelled without `onEnded` (e.g. the sheet appeared):
                // drop any pending hold and un-stick the zone.
                guard !active, phase != .idle else { return }
                holdTask?.cancel()
                holdTask = nil
                phase = .idle
            }
    }
}
