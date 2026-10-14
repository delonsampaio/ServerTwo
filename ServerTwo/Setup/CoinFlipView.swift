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
    /// Which team's letter the coin currently shows. A flat SwiftUI view
    /// rotated in 3D has no true "back face" to reveal mid-spin — this
    /// fakes a real flip by swapping the displayed letter a few times
    /// while `coinRotation` animates, landing on the actual outcome
    /// exactly when the spin stops.
    @State private var displayedTeam: Team = .teamA

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("\(setup.resolvedTeamAName) vs \(setup.resolvedTeamBName)")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            coin

            // The result text is always present (reserving its line's
            // height) and only its opacity toggles — if it were added via
            // `if let result`, the extra line appearing only once a result
            // exists would change this VStack's total content height, and
            // with Spacers above and below, SwiftUI would redistribute
            // space between them and visibly shift everything else when
            // the coin lands.
            Text("\(displayedTeam == .teamA ? setup.resolvedTeamAName : setup.resolvedTeamBName) serves first")
                .font(.title3.bold())
                .opacity(result == nil ? 0 : 1)
                .accessibilityIdentifier("FirstServeResult")

            if let result {
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
            Text(letter(for: displayedTeam))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .rotation3DEffect(.degrees(coinRotation), axis: (x: 0, y: 1, z: 0))
        .sensoryFeedback(.impact, trigger: result) { oldValue, newValue in
            newValue != nil
        }
    }

    private func letter(for team: Team) -> String {
        let name = team == .teamA ? setup.resolvedTeamAName : setup.resolvedTeamBName
        return String(name.prefix(1)).uppercased()
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
        // Toggles the displayed letter a few times while the spin
        // animates, so it actually reads as alternating between the two
        // teams rather than one static letter just distorting in place.
        let toggleInterval = 0.1
        let toggleCount = 6
        for step in 0..<toggleCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + toggleInterval * Double(step)) {
                displayedTeam = displayedTeam == .teamA ? .teamB : .teamA
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            isFlipping = false
            settle(on: outcome)
        }
    }

    private func settle(on team: Team) {
        result = team
        displayedTeam = team
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
