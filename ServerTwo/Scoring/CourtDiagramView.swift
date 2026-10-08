import SwiftUI
import PickleballKit

/// Shows which team is serving and which side (left/right) of the court
/// they're on, derived from score parity (even score → right side, odd →
/// left — the standard rule, not a new engine field). Diagram-only by
/// design (no visible text label), but carries a full `accessibilityLabel`
/// so VoiceOver users get the same information in words.
struct CourtDiagramView: View {
    let state: GameState

    private var servingTeamIsOnRightSide: Bool {
        state.score(for: state.servingTeam).isMultiple(of: 2)
    }

    var body: some View {
        HStack(spacing: 6) {
            courtHalf(isRight: false)
            courtHalf(isRight: true)
        }
        .frame(height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func courtHalf(isRight: Bool) -> some View {
        let isServingHalf = servingTeamIsOnRightSide == isRight
        return RoundedRectangle(cornerRadius: 8)
            .strokeBorder(.secondary, lineWidth: 1)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isServingHalf ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .overlay {
                if isServingHalf {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 14, height: 14)
                }
            }
    }

    private var accessibilityDescription: String {
        let teamName = state.servingTeam == .teamA ? "Team A" : "Team B"
        let side = servingTeamIsOnRightSide ? "right" : "left"
        return "\(teamName) serving, \(side) side, server \(state.serverNumber.rawValue)"
    }
}

#Preview {
    CourtDiagramView(state: GameState(
        teamAScore: 3,
        teamBScore: 2,
        servingTeam: .teamA,
        serverNumber: .one,
        teamATimeoutsRemaining: 2,
        teamBTimeoutsRemaining: 2,
        hasSideSwitched: false,
        lastPointWonWhileServing: true
    ))
    .padding()
}
