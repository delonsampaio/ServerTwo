import SwiftUI
import PickleballKit

/// Decides who serves first: flip the kit's coin, or enter the result of a
/// spin the players already did (same two routes as the phone, minimal).
struct CoinFlipView: View {
    /// What the sides are called: the chosen players, or "Team A" / "Team B".
    let teamAName: String
    let teamBName: String
    let onCancel: () -> Void
    let onBegin: (Team) -> Void

    @State private var firstServer: Team?
    /// The first server came from "X Won Spin", not from the coin.
    @State private var enteredByHand = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let first = firstServer {
                    // Two players ("A & B") take a plural verb.
                    Text("\(name(first)) \(name(first).contains(" & ") ? "serve" : "serves") first")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .accessibilityIdentifier("FirstServeResult")
                    Button { onBegin(first) } label: {
                        Text("Begin Match").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("Begin Match")
                    // A flip can be flipped again; a spin the players already
                    // did cannot (a random flip would overrule what they
                    // entered), so that one goes back to the choice instead.
                    if enteredByHand {
                        Button("Change") { firstServer = nil; enteredByHand = false }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("Change Server")
                    } else {
                        Button("Flip Again") { firstServer = CoinFlip.flip() }
                            .frame(minHeight: 44)
                    }
                } else {
                    Button { firstServer = CoinFlip.flip() } label: {
                        Text("Flip").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("Flip Coin")

                    Text("Already spun a paddle?")
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                    Button { firstServer = .teamA; enteredByHand = true } label: {
                        Text("\(teamAName) Won Spin")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("Team A Won Spin")
                    Button { firstServer = .teamB; enteredByHand = true } label: {
                        Text("\(teamBName) Won Spin")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("Team B Won Spin")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .centredTitleBar("Serve")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark", action: onCancel)
            }
        }
    }

    private func name(_ team: Team) -> String {
        team == .teamA ? teamAName : teamBName
    }
}
