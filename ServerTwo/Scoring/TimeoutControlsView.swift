import SwiftUI
import PickleballKit

struct TimeoutControlsView: View {
    let state: GameState
    let onRequestTimeout: (Team) -> Void

    var body: some View {
        HStack {
            timeoutButton(for: .teamA)
            Spacer()
            timeoutButton(for: .teamB)
        }
    }

    private func timeoutButton(for team: Team) -> some View {
        let remaining = state.timeoutsRemaining(for: team)
        let name = team == .teamA ? "Team A" : "Team B"
        return Button {
            onRequestTimeout(team)
        } label: {
            Label("Timeout (\(remaining))", systemImage: "hand.raised.fill")
        }
        .disabled(remaining <= 0)
        .buttonStyle(.bordered)
        .accessibilityLabel("\(name) timeout, \(remaining) remaining")
    }
}

#Preview {
    TimeoutControlsView(
        state: GameState(
            teamAScore: 3,
            teamBScore: 2,
            servingTeam: .teamA,
            serverNumber: .one,
            teamATimeoutsRemaining: 2,
            teamBTimeoutsRemaining: 1,
            hasSideSwitched: false,
            lastPointWonWhileServing: true
        ),
        onRequestTimeout: { _ in }
    )
    .padding()
}
