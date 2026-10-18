import SwiftUI
import PickleballKit

struct TimeoutControlsView: View {
    let state: GameState
    let onRequestTimeout: (Team) -> Void

    var body: some View {
        // Equal-width columns (not a Spacer pushing two independently-sized
        // buttons apart) so each button sits directly underneath its own
        // team's score card above, reading as one unified column per side.
        // At accessibility sizes two half-width buttons can't fit "Timeout (2)"
        // on one line (it broke mid-word), so they stack.
        AdaptiveStack(spacing: 12) {
            timeoutButton(for: .teamA)
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
                .frame(maxWidth: .infinity)
        }
        .disabled(remaining <= 0)
        .buttonStyle(.bordered)
        .controlSize(.large)
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
