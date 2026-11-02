import SwiftUI
import PickleballKit

/// Between games: who won, who serves next, the change of ends, then the next
/// game. Scoring is held here so a stray tap cannot score in the next game.
struct GameOverView: View {
    let session: StandaloneMatchSession

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                if let summary = session.lastCompletedGame {
                    // One line shorter than "Game 1 to Delon & Sarah", so
                    // "Next Game" stays on screen.
                    FittingTeamName(
                        variants: session.teamNameVariants(for: summary.winner),
                        suffix: session.isPair(summary.winner) ? " win" : " wins", lines: 2, minimumScale: 0.8
                    )
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    Text("\(summary.winnerScore) to \(summary.loserScore)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    if let next = summary.nextServingTeam {
                        FittingTeamName(
                            variants: session.teamNameVariants(for: next),
                            suffix: session.isPair(next) ? " serve next" : " serves next", lines: 2, minimumScale: 0.8
                        )
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    }
                }
                Text("Teams switch sides")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
                Button { session.startNextGame() } label: {
                    Text("Next Game").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("Next Game")
                // A mis-tap on the game-winning point is fixed here, not by
                // starting a game that has to be abandoned.
                Button {
                    session.undo()
                    WatchHaptics.playUndo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("Undo last point")
                .accessibilityIdentifier("Undo")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .centredTitleBar("Game Over")
    }
}
