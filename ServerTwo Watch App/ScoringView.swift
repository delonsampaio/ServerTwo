import SwiftUI
import PickleballKit

/// Two stacked, full-width tap zones (Team A on top, Team B below) and a
/// dedicated Undo button. Stacked rather than side by side so each zone is as
/// wide as the screen and a big score still fits at the largest text sizes.
struct ScoringView: View {
    let session: StandaloneMatchSession
    let workout: WorkoutController

    @State private var confirmingEnd = false
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @AppStorage(ScoringLayoutPreference.key) private var layout = ScoringLayout.stacked

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
                // The flow shows Home by itself once the session is idle.
                session.abandon()
            }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("The score will not be saved.")
        }
    }

    private var zones: some View {
        VStack(spacing: 4) {
            scoreZones
            // Undo keeps the room it needs; the call and then the heart rate
            // take what is left. On a narrow watch at a large text size the
            // heart rate is the first to go, never the call or Undo.
            ViewThatFits(in: .horizontal) {
                bottomRow(showingHeartRate: true)
                bottomRow(showingHeartRate: false)
            }
        }
        .scenePadding(.horizontal)
        // Every point of height goes to the tap zones: the Undo button's bottom
        // edge may run into the display's bottom margin (its corners follow the
        // screen's), which gives each zone more than the 44 pt minimum height
        // on the smaller watches.
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Team A on top or on the left, Team B below or on the right. Stacked
    /// zones are wide and thin; side-by-side zones are narrower but much
    /// taller, a thicker target for a quick tap (Rules > Layout).
    @ViewBuilder
    private var scoreZones: some View {
        if layout == .sideBySide {
            HStack(spacing: 4) {
                ScoreZone(session: session, team: .teamA, layout: layout)
                ScoreZone(session: session, team: .teamB, layout: layout)
            }
        } else {
            ScoreZone(session: session, team: .teamA, layout: layout)
            ScoreZone(session: session, team: .teamB, layout: layout)
        }
    }

    private func bottomRow(showingHeartRate: Bool) -> some View {
        HStack(spacing: 6) {
            undoButton
            if let call = session.scoreCall {
                scoreCallPill(call)
            }
            if showingHeartRate, let bpm = workout.heartRate, !isLuminanceReduced {
                heartRateReadout(bpm)
            }
        }
    }

    /// What the server says before serving ("7–5–2"): serving score, receiving
    /// score, server number. The zones are in fixed top and bottom order, so
    /// the serving score is not always the one on top. Doubles side-out only.
    /// Capped at `.large` like the heart rate, so it stays small beside Undo.
    private func scoreCallPill(_ call: String) -> some View {
        Text(call)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .overlay(Capsule().stroke(Color.secondary, lineWidth: 1))
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.spokenScoreCall ?? call)
            .accessibilityIdentifier("ScoreCall")
    }

    /// Keeps the flexible width and 44 pt height: the readouts beside it are
    /// small and only take what they need.
    private var undoButton: some View {
        Button {
            session.undo()
            // An undo can bring the "Switch back" notice up; one haptic,
            // the stronger one, not a click and then a notification.
            if session.sideSwitchNotice != nil {
                WatchHaptics.playNotice()
            } else {
                WatchHaptics.playUndo()
            }
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

    /// Hidden in Always-On and while no rate exists; the zones above keep their
    /// height because it shares the Undo row. Capped at `.large` so it
    /// stays small beside Undo.
    private func heartRateReadout(_ bpm: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill")
            Text("\(bpm)").monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.red)
        .lineLimit(1)
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate, \(bpm) beats per minute")
        .accessibilityIdentifier("HeartRate")
    }
}

private struct ScoreZone: View {
    let session: StandaloneMatchSession
    let team: Team
    let layout: ScoringLayout

    private var isServing: Bool { session.servingCaption(for: team) != nil }
    private var showsGames: Bool { session.matchFormat != .bestOfOne }

    var body: some View {
        Button {
            // The haptic goes in the callback, which runs before the snapshot
            // write, so it is not delayed by the disk. When the point raises
            // the side-switch notice only the stronger haptic plays.
            session.recordPoint(for: team) { outcome in
                if session.sideSwitchNotice != nil {
                    WatchHaptics.playNotice()
                } else {
                    WatchHaptics.play(for: outcome)
                }
            }
        } label: {
            Group {
                if layout == .sideBySide { sideBySideLabel } else { stackedLabel }
            }
            .foregroundStyle(.white)
            // A zone is a fixed-height surface (two share the screen with
            // Undo), so its text stops growing at xLarge instead of clipping;
            // VoiceOver reads the full label whatever the size.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .padding(.horizontal, 10)
            // 44 pt floor: with large system text the title and Undo grow and
            // squeeze the zones, which must never get shorter than a tap target.
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
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

    private var caption: String { session.servingCaption(for: team) ?? session.tapCaption(for: team) }

    /// The longest form of the team name that fits the zone: the full name,
    /// then first name and last initial ("Delon S. & Mike R."), then first
    /// names. Only the shortest may wrap or be cut off. VoiceOver reads the
    /// full name from the zone's label.
    private func teamNameText(lines: Int, minimumScale: CGFloat) -> some View {
        let variants = session.teamNameVariants(for: team)
        return ViewThatFits(in: .horizontal) {
            ForEach(variants.dropLast(), id: \.self) { name in
                Text(name).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            Text(variants.last ?? session.teamName(for: team))
                .lineLimit(lines)
                .minimumScaleFactor(minimumScale)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
    }

    /// Full-width zone: names and caption on the left, the score on the right.
    private var stackedLabel: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                // Players' names can be long ("Mike & Sarah"): the longest
                // form that fits on one line, shrunk a little at the last
                // step, then cut off at the end.
                teamNameText(lines: 1, minimumScale: 0.75)
                // The serving badge says who is up, in words, so the cue is
                // never colour alone; the receiving zone says what a tap
                // does, because it is not a point.
                Text(caption)
                    .font(.caption2.weight(isServing ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if showsGames {
                    Text("Games \(session.gamesWon(for: team))")
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            Spacer(minLength: 0)
            // The score keeps its room: a long name gives way to it, never
            // the other way round.
            Text("\(session.score(for: team))")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)
        }
    }

    /// Half-width zone, name on top, the score in the middle, then the caption:
    /// the text wraps to two lines because each zone is only about half as wide.
    private var sideBySideLabel: some View {
        VStack(spacing: 2) {
            teamNameText(lines: 2, minimumScale: 0.7)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Text("\(session.score(for: team))")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)
            Spacer(minLength: 0)
            // "Tap for 2nd Server" is too long for half a screen; the zone
            // itself says it is a tap. VoiceOver keeps the full hint.
            // Footnote size, a step above the stacked layout's caption2: this
            // is the line that says who serves.
            Text(caption.replacingOccurrences(of: "Tap for ", with: ""))
                .font(.footnote.weight(isServing ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if showsGames {
                Text("Games \(session.gamesWon(for: team))")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
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
