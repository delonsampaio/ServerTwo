import SwiftUI
import PickleballKit

/// Two stacked, full-width tap zones (Team A on top, Team B below) and a
/// dedicated Undo button. Stacked rather than side by side so each zone is as
/// wide as the screen and a big score still fits at the largest text sizes.
struct ScoringView: View {
    let session: StandaloneMatchSession
    let onAbandon: () -> Void

    @State private var confirmingEnd = false

    var body: some View {
        Group {
            if let direction = session.sideSwitchNotice {
                SideSwitchNoticeView(
                    direction: direction,
                    threshold: session.configuration?.winningScore.sideSwitchThreshold ?? 0,
                    onAcknowledge: { session.acknowledgeSideSwitchNotice() }
                )
            } else {
                zones
            }
        }
        .navigationTitle(session.matchFormat == .bestOfOne ? "Match" : "Game \(session.currentGameIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End Match", systemImage: "xmark") { confirmingEnd = true }
                    .accessibilityIdentifier("End Match")
            }
        }
        .alert("End match?", isPresented: $confirmingEnd) {
            Button("End Match", role: .destructive) {
                session.abandon()
                onAbandon()
            }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("The score will not be saved.")
        }
        .onChange(of: session.sideSwitchNotice) { _, notice in
            if notice != nil { WatchHaptics.playNotice() }
        }
    }

    private var zones: some View {
        VStack(spacing: 4) {
            ScoreZone(session: session, team: .teamA)
            ScoreZone(session: session, team: .teamB)
            Button {
                session.undo()
                WatchHaptics.playUndo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!session.canUndo)
            .accessibilityLabel("Undo last point")
            .accessibilityIdentifier("Undo")
        }
        .scenePadding(.horizontal)
        // Every point of height goes to the tap zones: the Undo button's bottom
        // edge may run into the display's bottom margin (its corners follow the
        // screen's), which gives each zone more than the 44 pt minimum height
        // on the smaller watches.
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct ScoreZone: View {
    let session: StandaloneMatchSession
    let team: Team

    private var isServing: Bool { session.servingCaption(for: team) != nil }
    private var showsGames: Bool { session.matchFormat != .bestOfOne }

    var body: some View {
        Button {
            let outcome = session.recordPoint(for: team)
            WatchHaptics.play(for: outcome)
        } label: {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.teamName(for: team))
                        .font(.footnote.weight(.semibold))
                    // The serving badge says who is up, in words, so the cue is
                    // never colour alone; the receiving zone says what a tap
                    // does, because it is not a point.
                    Text(session.servingCaption(for: team) ?? session.tapCaption(for: team))
                        .font(.caption2.weight(isServing ? .bold : .regular))
                    if showsGames {
                        Text("Games \(session.gamesWon(for: team))")
                            .font(.caption2)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                Text("\(session.score(for: team))")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(.white)
            // A zone is a fixed-height surface (two share the screen with
            // Undo), so its text stops growing at xLarge instead of clipping;
            // VoiceOver reads the full label whatever the size.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The serving team's zone is solid accent, the other a quiet
            // tint of it: a glanceable cue that backs up the text badge.
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(isServing ? 1 : 0.28))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.spokenSummary(for: team))
        .accessibilityHint(session.tapCaption(for: team))
        .accessibilityIdentifier(team == .teamA ? "Team A Zone" : "Team B Zone")
    }
}

/// The mid-game change of ends, in the deciding game only. Replaces the zones
/// (instead of overlaying them) so a tap meant to dismiss it cannot score.
private struct SideSwitchNoticeView: View {
    let direction: SideSwitchDirection
    let threshold: Int
    let onAcknowledge: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(direction == .switchSides ? "Switch sides" : "Switch back")
                    .font(.headline)
                Text(direction == .switchSides
                     ? "A team reached \(threshold). Change ends."
                     : "The score went back under \(threshold). Return to your starting ends.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button(action: onAcknowledge) {
                    Text("OK").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("Dismiss Side Switch")
            }
        }
    }
}
