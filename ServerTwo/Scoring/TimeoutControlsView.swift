import SwiftUI
import PickleballKit

struct TimeoutControlsView: View {
    let state: GameState
    let teamAName: String
    let teamBName: String
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
        let name = team == .teamA ? teamAName : teamBName
        return Button {
            onRequestTimeout(team)
        } label: {
            Label("Timeout (\(remaining))", systemImage: "hand.raised.fill")
                .frame(maxWidth: .infinity)
        }
        .disabled(remaining <= 0)
        .buttonStyle(.bordered)
        // A bordered button fills with the tint and draws its label in it too,
        // which never reaches 4.5:1 for a blue on its own blue wash: keep the
        // blue wash (`accentText` tint) and set the label in `.primary`.
        .tint(Color.accentText)
        .foregroundStyle(.primary)
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
        teamAName: "Alice & Bob",
        teamBName: "Team B",
        onRequestTimeout: { _ in }
    )
    .padding()
}
