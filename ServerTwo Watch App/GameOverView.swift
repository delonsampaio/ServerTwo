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
                    Text("Game \(summary.gameNumber) to \(session.teamName(for: summary.winner))")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("\(summary.winnerScore) to \(summary.loserScore)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    if let next = summary.nextServingTeam {
                        Text("Next game, \(session.teamName(for: next)) serving")
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
        .navigationTitle("Game Over")
        .navigationBarTitleDisplayMode(.inline)
    }
}
