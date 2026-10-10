import SwiftUI
import PickleballKit

struct ScoringView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    @Environment(AppSettings.self) private var appSettings

    @State private var correctingTeam: Team?
    @State private var showingSideSwitchAlert = false
    @State private var sideSwitchAcknowledgedForGameIndex = -1
    @State private var sideSwitchAcknowledgedViaCorrectionForGameIndex = -1
    @State private var showingGameOverAlert = false
    @State private var gameOverAcknowledgedForGameIndex = -1
    @State private var gameOverMessage = ""
    @State private var showingFinishConfirmation = false
    @State private var finishErrorMessage: String?

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
        .sheet(isPresented: Binding(
            get: { correctingTeam != nil },
            set: { isPresented in if !isPresented { correctingTeam = nil } }
        ), onDismiss: {
            // The side-switch check has a same-transaction presentation race:
            // `PickleballGame.correctScore` also calls `checkSideSwitch()`, so a
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
            // the onChange handler's own alert silently failed to present.
            if let match = activeMatchController.match {
                let gameIndex = match.completedGames.count
                if match.currentGame.state.hasSideSwitched, sideSwitchAcknowledgedViaCorrectionForGameIndex != gameIndex {
                    sideSwitchAcknowledgedViaCorrectionForGameIndex = gameIndex
                    sideSwitchAcknowledgedForGameIndex = gameIndex
                    showingSideSwitchAlert = true
                }
            }
        }) {
            if let match = activeMatchController.match, let team = correctingTeam {
                ScoreCorrectionSheet(
                    teamDisplayName: team == .teamA ? activeMatchController.teamAName : activeMatchController.teamBName,
                    currentScore: match.currentGame.state.score(for: team),
                    onCommit: { newScore in
                        activeMatchController.correctScore(team: team, to: newScore)
                    }
                )
            }
        }
        .onChange(of: activeMatchController.match.map(ObjectIdentifier.init)) { _, _ in
            // A new match (including a fresh one right after finishing the
            // previous one) must re-arm the side-switch alert — without this,
            // acknowledging the side switch in one match can suppress the
            // alert for every subsequent match's first side switch, since
            // completedGames.count restarts at 0 each time and would otherwise
            // collide with a previously-acknowledged index.
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
            if let finishedGame = match.completedGames.last {
                let aScore = finishedGame.state.teamAScore
                let bScore = finishedGame.state.teamBScore
                gameOverMessage = """
                    Game \(newCount): \(activeMatchController.teamAName) \(aScore) - \(activeMatchController.teamBName) \(bScore).
                    Games: \(match.gamesWon(for: .teamA)) – \(match.gamesWon(for: .teamB)). Next game starts at 0-0.
                    """
            } else {
                gameOverMessage = "Next game starts at 0-0."
            }
            showingGameOverAlert = true
        }
        .onChange(of: activeMatchController.match?.currentGame.state.hasSideSwitched) { _, hasSideSwitched in
            guard let match = activeMatchController.match else { return }
            let gameIndex = match.completedGames.count
            if hasSideSwitched == true, sideSwitchAcknowledgedForGameIndex != gameIndex {
                sideSwitchAcknowledgedForGameIndex = gameIndex
                showingSideSwitchAlert = true
            }
        }
        .alert("Side Switch", isPresented: $showingSideSwitchAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Time to switch sides of the court.")
        }
        .alert("Game Over", isPresented: $showingGameOverAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(gameOverMessage)
        }
        .alert("Save Failed", isPresented: Binding(
            get: { finishErrorMessage != nil },
            set: { isPresented in if !isPresented { finishErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(finishErrorMessage ?? "")
        }
        .confirmationDialog("Finish Match?", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
            Button("Confirm Finish") {
                // A save failure used to be swallowed by `try?`, leaving the
                // user stuck on a finished match with no feedback at all.
                do {
                    try activeMatchController.finishMatch()
                } catch {
                    finishErrorMessage = "Couldn't save this match. Please try again."
                }
            }
            .accessibilityIdentifier("Confirm Finish")
            Button("Cancel", role: .cancel) { }
        } message: {
            if let match = activeMatchController.match {
                Text(finishSummary(for: match))
            }
        }
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
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            CourtDiagramView(state: match.currentGame.state)
                .padding(.horizontal)

            HStack(spacing: 2) {
                scoreZone(for: .teamA, match: match)
                scoreZone(for: .teamB, match: match)
            }

            // Hidden once the match is decided — there's no more play left to
            // pause, and showing them pushed the "Finish Match" button's
            // position around every time a match ended. isMatchOver is
            // computed live from the current score, so undoing the winning
            // point un-finishes the match and these reappear automatically.
            if !match.isMatchOver {
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
        return Button {
            activeMatchController.recordPoint(for: team)
        } label: {
            VStack(spacing: 8) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(score)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Spec §3.7 scopes haptics into this phase's ScoringView work. The
        // condition closure both respects the user's toggle and limits firing
        // to actual score increases, so an unrelated re-render or an undo
        // doesn't buzz.
        .sensoryFeedback(.impact, trigger: score) { oldValue, newValue in
            appSettings.hapticsEnabled && newValue > oldValue
        }
        .onLongPressGesture {
            correctingTeam = team
        }
        .disabled(match.isMatchOver)
        .accessibilityIdentifier("scoreZone.\(team.rawValue)")
        .accessibilityLabel("\(name), \(score) points. Tap to score, double tap and hold to correct.")
    }

    /// For best-of-1 the point score IS the match result; for multi-game
    /// formats the last game's point score is misleading (it reports one game,
    /// not the match), so report games-won instead.
    private func finishSummary(for match: PickleballMatch) -> String {
        if match.matchFormat == .bestOfOne {
            let aScore = match.currentGame.state.teamAScore
            let bScore = match.currentGame.state.teamBScore
            return "Final score: \(activeMatchController.teamAName) \(aScore) - \(activeMatchController.teamBName) \(bScore)"
        }
        let aGames = match.gamesWon(for: .teamA)
        let bGames = match.gamesWon(for: .teamB)
        return "Final score: \(activeMatchController.teamAName) \(aGames) - \(activeMatchController.teamBName) \(bGames) games"
    }
}
