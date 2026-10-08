import SwiftUI
import PickleballKit

struct ScoringView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController

    @State private var correctingTeam: Team?
    @State private var showingSideSwitchAlert = false
    @State private var sideSwitchAcknowledgedForGameIndex = -1
    @State private var showingFinishConfirmation = false
    @State private var isShowingPaywall = false

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
        )) {
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
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .onChange(of: activeMatchController.match?.currentGame.state.hasSideSwitched) { _, hasSideSwitched in
            guard let match = activeMatchController.match else { return }
            let gameIndex = match.completedGames.count
            if hasSideSwitched == true, sideSwitchAcknowledgedForGameIndex != gameIndex {
                sideSwitchAcknowledgedForGameIndex = gameIndex
                showingSideSwitchAlert = true
            }
        }
        .onChange(of: activeMatchController.match?.isPaywalled) { _, isPaywalled in
            if isPaywalled == true {
                isShowingPaywall = true
            }
        }
        .alert("Side Switch", isPresented: $showingSideSwitchAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Time to switch sides of the court.")
        }
        .confirmationDialog("Finish Match?", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
            Button("Confirm Finish") {
                try? activeMatchController.finishMatch()
            }
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
            CourtDiagramView(state: match.currentGame.state)
                .padding(.horizontal)

            HStack(spacing: 2) {
                scoreZone(for: .teamA, match: match)
                scoreZone(for: .teamB, match: match)
            }

            TimeoutControlsView(state: match.currentGame.state) { team in
                activeMatchController.requestTimeout(for: team)
            }
            .padding(.horizontal)

            if match.isPaywalled {
                Button("Demo Limit Reached — Unlock to Continue") {
                    isShowingPaywall = true
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }

            if match.isMatchOver {
                Button("Finish Match") {
                    showingFinishConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
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
        .onLongPressGesture {
            correctingTeam = team
        }
        .disabled(match.isMatchOver)
        .accessibilityIdentifier("scoreZone.\(team.rawValue)")
        .accessibilityLabel("\(name), \(score) points. Tap to score, double tap and hold to correct.")
    }

    private func finishSummary(for match: PickleballMatch) -> String {
        let aScore = match.currentGame.state.teamAScore
        let bScore = match.currentGame.state.teamBScore
        return "Final score: \(activeMatchController.teamAName) \(aScore) - \(activeMatchController.teamBName) \(bScore)"
    }
}
