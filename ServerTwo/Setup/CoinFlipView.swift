import SwiftUI
import SwiftData
import PickleballKit

/// Shown by `RootTabView` whenever `ActiveMatchController.pendingMatchSetup`
/// is non-nil — i.e. "Start Match" was tapped in `MatchSetupView`, but who
/// serves first hasn't been decided yet. `PickleballMatch` requires that at
/// construction, so this screen is what turns a staged setup into a real,
/// scoring match.
///
/// The manual "Won Spin" buttons are front and center, not gated behind the
/// animation — most players already settle this with a physical paddle
/// spin before ever opening the app, so forcing them to watch a redundant
/// digital flip finish first would just be friction on top of a
/// real-world decision already made.
struct CoinFlipView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    let setup: PendingMatchSetup

    @State private var isFlipping = false
    @State private var coinRotation: Double = 0
    @State private var result: Team?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("\(setup.resolvedTeamAName) vs \(setup.resolvedTeamBName)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            coin

            if let result {
                Text("\(result == .teamA ? setup.resolvedTeamAName : setup.resolvedTeamBName) serves first")
                    .font(.title3.bold())
                    .accessibilityIdentifier("FirstServeResult")
                Button("Begin Match") {
                    activeMatchController.confirmFirstServe(result)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("Begin Match")
            } else {
                Button("Flip Coin") {
                    flip()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isFlipping)
                .accessibilityIdentifier("Flip Coin")
            }

            Spacer()

            VStack(spacing: 12) {
                Text("Already spun a paddle?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Button("\(setup.resolvedTeamAName) Won Spin") {
                        settle(on: .teamA)
                    }
                    .accessibilityIdentifier("Team A Won Spin")
                    Button("\(setup.resolvedTeamBName) Won Spin") {
                        settle(on: .teamB)
                    }
                    .accessibilityIdentifier("Team B Won Spin")
                }
                .buttonStyle(.bordered)
            }

            Button("Cancel", role: .cancel) {
                activeMatchController.cancelPendingMatch()
            }
            .accessibilityIdentifier("Cancel Coin Flip")
        }
        .padding()
        .navigationTitle("First Serve")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }

    private var coin: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 100, height: 100)
            Image(systemName: "circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.9))
        }
        .rotation3DEffect(.degrees(coinRotation), axis: (x: 0, y: 1, z: 0))
        .sensoryFeedback(.impact, trigger: result) { oldValue, newValue in
            newValue != nil
        }
    }

    private func flip() {
        isFlipping = true
        let outcome = CoinFlip.flip()
        // Several full spins, slowing to a stop — "coinRotation" keeps
        // incrementing across repeated flips (never reset to 0) so a
        // second flip always visibly spins forward again, rather than
        // snapping back through a full reverse rotation first.
        withAnimation(.easeOut(duration: 0.7)) {
            coinRotation += 360 * 3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            isFlipping = false
            settle(on: outcome)
        }
    }

    private func settle(on team: Team) {
        result = team
    }
}

#Preview {
    NavigationStack {
        CoinFlipView(setup: PendingMatchSetup(
            configuration: GameConfiguration(),
            matchFormat: .bestOfOne,
            teamAName: "Delon",
            teamBName: "Yi",
            teamAPlayerIDs: [],
            teamBPlayerIDs: []
        ))
    }
    .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
}
