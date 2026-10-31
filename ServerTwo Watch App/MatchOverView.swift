import SwiftUI
import PickleballKit

struct MatchOverView: View {
    let session: StandaloneMatchSession
    @State private var saveFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                if let winner = session.matchWinner {
                    Text("\(session.teamName(for: winner)) wins")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                if session.matchFormat != .bestOfOne {
                    Text("\(session.gamesWon(for: .teamA)) to \(session.gamesWon(for: .teamB)) in games")
                        .font(.footnote)
                }
                Text(finalScores)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("FinalScores")
                Button {
                    do {
                        try session.dismissFinishedMatch()
                        WatchHaptics.playDone()
                    } catch {
                        saveFailed = true
                    }
                } label: {
                    Text("Done").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("Done")
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
        .navigationTitle("Match Over")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't save the match", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tap Done to try again.")
        }
    }

    /// "11-3, 9-11, 11-7", every game in order.
    private var finalScores: String {
        session.completedGameScores.map { "\($0.teamA)-\($0.teamB)" }.joined(separator: ", ")
    }
}
