import SwiftUI
import PickleballKit

struct ScoringView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    @Environment(AppSettings.self) private var appSettings
    @Environment(VoiceAnnouncer.self) private var voiceAnnouncer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Both are today's fixed sizes at the default text size and scale with
    // Dynamic Type from there. The digit growth is capped (see `scoreZone`).
    @ScaledMetric(relativeTo: .largeTitle) private var scoreDigitSize: CGFloat = 108
    private let scoreDigitSizeCap: CGFloat = 128

    @State private var isShowingScoreCorrection = false
    @State private var sideSwitchTracker = SideSwitchPromptTracker()
    // `onChange` doesn't fire for a view's initial value, so a match restored
    // after a relaunch (flag may already be set) must be seeded once on appear.
    @State private var didSeedSideSwitchTracker = false
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
    // The two sheets a prompt must wait for, tracked by whether they are REALLY
    // on screen (set in their content's `onAppear`, cleared only in their
    // `onDismiss`), not by their `isPresented` bindings: a Save sets the
    // binding false in the same action that commits, while the sheet is still
    // animating out. A prompt presented in that window can be dropped by
    // SwiftUI, leaving `prompt` non-nil with no sheet and blocking every later
    // prompt.
    @State private var correctionSheetOnScreen = false
    @State private var finishSheetOnScreen = false

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
            // `PickleballGame.correctScores` also calls `checkSideSwitch()`, so
            // a correction can flip `hasSideSwitched` inside the sheet's
            // `onCommit`, in the same transaction as its own `dismiss()`. The
            // `.onChange(of: ...hasSideSwitched)` handler below normally
            // catches that and queues the prompt, but this idempotent re-check
            // guarantees it once the sheet is really gone; if the handler
            // already queued it, the tracker sees nothing left to announce.
            correctionSheetOnScreen = false
            syncSideSwitchPrompt()
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
                .onAppear { correctionSheetOnScreen = true }
            }
        }
        .onAppear {
            guard !didSeedSideSwitchTracker else { return }
            didSeedSideSwitchTracker = seedSideSwitchTracker()
        }
        .onChange(of: activeMatchController.match.map(ObjectIdentifier.init)) { _, _ in
            // Defensive reset for the controller swapping to a different match
            // while this view stays alive: queued/visible prompts and the
            // per-game trackers belong to the old match, and
            // completedGames.count restarts at 0, which would collide with old
            // indexes. In practice `RootTabView` removes this view whenever
            // `match` is nil, so a new match normally gets a fresh view (seeded
            // in `onAppear`) and this does not run.
            prompt = nil
            pendingPrompts = []
            didSeedSideSwitchTracker = seedSideSwitchTracker()
            gameOverAcknowledgedForGameIndex = -1
        }
        .onChange(of: activeMatchController.match.map { AnnouncementSnapshot(match: $0) }) { old, new in
            // `onChange` does not fire for the initial value, so a resumed match
            // stays silent until its next change. Derived from state (not from
            // which button was pressed) so taps, undo, a Correct Score save and
            // accessibility actions all announce the same way.
            guard let match = activeMatchController.match, let old, let new else { return }
            voiceAnnouncer.announce(AnnouncementPlanner.plan(
                from: old, to: new,
                configuration: match.configuration, matchFormat: match.matchFormat,
                teamAName: activeMatchController.teamAName,
                teamBName: activeMatchController.teamBName
            ))
        }
        .onChange(of: activeMatchController.match?.completedGames.count) { _, newCount in
            // A completed game that doesn't end the match silently resets the
            // visible point score to 0-0. Without feedback that reads as lost
            // data, so acknowledge each newly-completed game once. The tracking
            // var holds the INDEX of the game already acknowledged, and game
            // index i completes when completedGames.count becomes i + 1 — hence
            // the `+ 1` on both sides.
            guard let match = activeMatchController.match, let newCount else { return }
            // Also lowers the index when the count drops (undo), so replaying
            // the game-ending point announces it again.
            let decision = ScoringPrompt.gameOverDecision(
                newCompletedCount: newCount,
                acknowledgedIndex: gameOverAcknowledgedForGameIndex,
                isMatchOver: match.isMatchOver
            )
            gameOverAcknowledgedForGameIndex = decision.acknowledgedIndex
            guard decision.shouldPrompt else { return }
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
                    teamBGames: match.gamesWon(for: .teamB),
                    // `completedGames.last` is the game just finished; the match
                    // has already created the next game, so `currentGame` is its
                    // fresh game and its initial serving team is the next first server.
                    firstServerName: match.currentGame.initialServingTeam == .teamA
                        ? activeMatchController.teamAName
                        : activeMatchController.teamBName
                ))
            }
        }
        .onChange(of: activeMatchController.match?.currentGame.state.hasSideSwitched) { _, _ in
            syncSideSwitchPrompt()
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
        .sheet(isPresented: $showingFinishConfirmation, onDismiss: {
            finishSheetOnScreen = false
            presentNextPromptIfPossible()
        }) {
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
                .onAppear { finishSheetOnScreen = true }
            }
        }
    }

    /// Returns whether it seeded (false only when there is no match yet).
    private func seedSideSwitchTracker() -> Bool {
        guard let match = activeMatchController.match else { return false }
        sideSwitchTracker.seed(
            completedGameFlags: match.completedGames.map(\.state.hasSideSwitched),
            currentGameFlag: match.currentGame.state.hasSideSwitched
        )
        return true
    }

    /// Idempotent (see `SideSwitchPromptTracker`), so it can be called from
    /// every place the flag might have changed without double-prompting.
    private func syncSideSwitchPrompt() {
        guard let match = activeMatchController.match, !match.isMatchOver else { return }
        let gameIndex = match.completedGames.count
        // The mid-game end change applies only in the last game of the match
        // format (Rule 21.B). Between games teams always change ends (Rule
        // 21.F.2), which the Game Over sheet and the spoken game line say.
        guard match.matchFormat.isLastGame(index: gameIndex) else { return }
        guard let direction = sideSwitchTracker.next(
            gameIndex: gameIndex, hasSwitched: match.currentGame.state.hasSideSwitched
        ) else { return }
        enqueue(.sideSwitch(
            gameIndex: gameIndex,
            direction: direction,
            threshold: match.configuration.winningScore.sideSwitchThreshold,
            teamAName: activeMatchController.teamAName,
            teamBName: activeMatchController.teamBName,
            teamAScore: match.currentGame.state.teamAScore,
            teamBScore: match.currentGame.state.teamBScore
        ))
    }

    private func enqueue(_ newPrompt: ScoringPrompt) {
        // A double tap on the toolbar button must not stack two Cancel
        // prompts. Game Over / Side Switch may legitimately repeat.
        if case .cancelMatch = newPrompt,
           prompt?.id == newPrompt.id || pendingPrompts.contains(where: { $0.id == newPrompt.id }) {
            return
        }
        pendingPrompts.append(newPrompt)
        presentNextPromptIfPossible()
    }

    /// Shows the next queued prompt unless something is already on screen.
    /// Called after every enqueue and whenever a sheet this view owns is
    /// dismissed, so a prompt that had to wait appears right after the sheet
    /// that blocked it.
    private func presentNextPromptIfPossible() {
        guard prompt == nil,
              !isShowingScoreCorrection, !correctionSheetOnScreen,
              !showingFinishConfirmation, !finishSheetOnScreen else { return }
        if let match = activeMatchController.match {
            // Drop side-switch prompts that went stale while waiting (e.g. the
            // same save crossed the threshold and ended the game). The tracker
            // is re-synced to the live flag so the dropped one can't leave it
            // claiming the user was told something they never saw.
            let gameIndex = match.completedGames.count
            let live = match.currentGame.state.hasSideSwitched
            pendingPrompts.removeAll { queued in
                guard queued.isStale(currentGameIndex: gameIndex, hasSideSwitched: live) else { return false }
                if case let .sideSwitch(queuedIndex, _, _, _, _, _, _) = queued, queuedIndex == gameIndex {
                    sideSwitchTracker.resync(gameIndex: queuedIndex, to: live)
                }
                return true
            }
        }
        guard !pendingPrompts.isEmpty else { return }
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
            ServingBadgeSlot(isServing: isServing)
                // Capped at the first accessibility size: the badge sits in a
                // half-width card, where "SERVING" at the largest sizes would
                // truncate.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

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
                // A long name wraps onto a second line at accessibility
                // sizes instead of shrinking or truncating.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.6)
                .multilineTextAlignment(.center)
            // The digits scale with Dynamic Type but stop at 128 pt, and never
            // wrap: a two-digit score must fit the half-width card.
            Text("\(score)")
                .font(.system(size: min(scoreDigitSize, scoreDigitSizeCap), weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Spacer()

            Text("Tap to Score")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                // Wraps at accessibility sizes; never squeezed into a truncation.
                .fixedSize(horizontal: false, vertical: true)
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

/// The fixed-height slot at the top of a score card: the "SERVING" badge when
/// this team serves, otherwise empty space of the same height — if the
/// receiving side left it empty with nothing reserving the space, its card's
/// content would sit lower than the serving side's, breaking the side-by-side
/// alignment the two cards are supposed to share. 28 pt at the default text
/// size, scaling with the (capped) Dynamic Type size.
private struct ServingBadgeSlot: View {
    let isServing: Bool
    @ScaledMetric(relativeTo: .caption) private var slotHeight: CGFloat = 28

    var body: some View {
        Group {
            if isServing {
                Label("SERVING", systemImage: "circle.grid.cross.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            } else {
                Color.clear
            }
        }
        .frame(height: slotHeight)
    }
}

/// Tap to score, hold to correct — decided from the touch's own timing so a
/// press of ANY length shorter than `holdDuration` is a tap. SwiftUI's
/// `.onTapGesture` + `.onLongPressGesture` pair left a dead zone: a press
/// longer than a quick tap but shorter than the long-press duration did
/// nothing, silently dropping points on a slightly slow tap.
struct TapOrHoldModifier: ViewModifier {
    let holdDuration: Duration
    let onTap: () -> Void
    let onHold: () -> Void

    /// Travel beyond this many points means the touch is a drag, not a tap or
    /// a hold. Internal (not private) so the boundary can be unit-tested.
    static let tapMovementThreshold: CGFloat = 20

    static func isMovementBeyondTapThreshold(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) > tapMovementThreshold
    }

    private enum Phase { case idle, pressing, holdFired, moved }
    @State private var phase: Phase = .idle
    // Resets to false automatically when the touch ends OR is cancelled, so a
    // touch that never delivers `onEnded` can't leave the zone stuck. A plain
    // phase flag can't do that: it only changes in `onChanged`/`onEnded`,
    // neither of which runs for a cancelled touch.
    @GestureState private var touchActive = false
    @State private var holdTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .opacity(phase == .pressing ? 0.7 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touchActive) { _, state, _ in state = true }
                    .onChanged { value in
                        // Dragging past the tap threshold while still pressing
                        // cancels the pending hold; releasing then does nothing.
                        if phase == .pressing,
                           Self.isMovementBeyondTapThreshold(translation: value.translation) {
                            holdTask?.cancel()
                            holdTask = nil
                            phase = .moved
                            return
                        }
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
                        let moved = Self.isMovementBeyondTapThreshold(translation: value.translation)
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
            .onDisappear {
                // A stale timer must not fire `onHold` after the screen is gone.
                holdTask?.cancel()
                holdTask = nil
                phase = .idle
            }
    }
}
