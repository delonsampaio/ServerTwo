import SwiftUI
import PickleballKit

/// Decides who serves first: flip the kit's coin, or enter the result of a
/// spin the players already did (same two routes as the phone, minimal).
struct CoinFlipView: View {
    let onCancel: () -> Void
    let onBegin: (Team) -> Void

    @State private var firstServer: Team?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let first = firstServer {
                    Text("\(name(first)) serves first")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("FirstServeResult")
                    Button { onBegin(first) } label: {
                        Text("Begin Match").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("Begin Match")
                    Button("Flip Again") { firstServer = CoinFlip.flip() }
                        .frame(minHeight: 44)
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
                    Button { firstServer = .teamA } label: {
                        Text("Team A Won Spin").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("Team A Won Spin")
                    Button { firstServer = .teamB } label: {
                        Text("Team B Won Spin").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("Team B Won Spin")
                }
            }
        }
        .navigationTitle("Serve")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark", action: onCancel)
            }
        }
    }

    private func name(_ team: Team) -> String {
        team == .teamA ? StandaloneMatchSession.teamAName : StandaloneMatchSession.teamBName
    }
}
