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
        .navigationBarTitleDisplayMode(.inline)
        .centredTitleBar(session.matchFormat == .bestOfOne ? "Match" : "Game \(session.currentGameIndex + 1)")
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
            // take what is left. In doubles side-out on a small watch the word
            // "Undo" does not leave room for the heart rate, so Undo first
            // shrinks to its icon; only then does the heart rate go, never the
            // call or Undo.
            ViewThatFits(in: .horizontal) {
                bottomRow(showingHeartRate: true, compactUndo: false)
                bottomRow(showingHeartRate: true, compactUndo: true)
                bottomRow(showingHeartRate: false, compactUndo: false)
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
    ///
    /// Both zones show the same form of the name: the longest level (full
    /// names, first name and last initial, first names) at which both fit, so
    /// the pair never reads "Delon Sampaio" beside "Priya R.". Only the last
    /// level may wrap or be cut off.
    private var scoreZones: some View {
        let levels = max(session.teamNameVariants(for: .teamA).count, session.teamNameVariants(for: .teamB).count)
        return ViewThatFits(in: .horizontal) {
            ForEach(0..<levels, id: \.self) { level in
                zonePair(nameLevel: level, wrapsName: level == levels - 1)
            }
        }
    }

    @ViewBuilder
    private func zonePair(nameLevel: Int, wrapsName: Bool) -> some View {
        if layout == .sideBySide {
            EqualWidthHStack(spacing: 4) {
                ScoreZone(session: session, team: .teamA, layout: layout, nameLevel: nameLevel, wrapsName: wrapsName)
                ScoreZone(session: session, team: .teamB, layout: layout, nameLevel: nameLevel, wrapsName: wrapsName)
            }
        } else {
            VStack(spacing: 4) {
                ScoreZone(session: session, team: .teamA, layout: layout, nameLevel: nameLevel, wrapsName: wrapsName)
                ScoreZone(session: session, team: .teamB, layout: layout, nameLevel: nameLevel, wrapsName: wrapsName)
            }
        }
    }

    private func bottomRow(showingHeartRate: Bool, compactUndo: Bool) -> some View {
        HStack(spacing: 6) {
            undoButton(compact: compactUndo)
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
            .frame(minHeight: 36, maxHeight: 36)
            .overlay(Capsule().stroke(Color.secondary, lineWidth: 1))
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.spokenScoreCall ?? call)
            .accessibilityIdentifier("ScoreCall")
    }

    /// Keeps the flexible width at 36 pt tall, not 44: it is the least-used
    /// button, and the points go to the tap zones. The readouts beside it are
    /// small and only take what they need.
    private func undoButton(compact: Bool) -> some View {
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
            Group {
                if compact {
                    Image(systemName: "arrow.uturn.backward")
                } else {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            }
            .font(.footnote.weight(.semibold))
            // Drawn here rather than by `.bordered`, which adds its own
            // padding outside the frame (a "36 pt" Undo was 40 pt tall, taller
            // than the call beside it and 4 pt out of the zones' height).
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            .background(Color.white.opacity(0.2), in: Capsule())
            .opacity(session.canUndo ? 1 : 0.4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
    /// Which form of the team name to show (see `ScoringView.scoreZones`), and
    /// whether this is the last, shortest one, which may wrap or be cut off.
    let nameLevel: Int
    let wrapsName: Bool

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
            // Half-width zones give up some side padding to the name and caption.
            .padding(.horizontal, layout == .sideBySide ? 6 : 10)
            .padding(.vertical, layout == .sideBySide ? 3 : 0)
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

    /// The name at this zone's level. Every level but the last stays on one
    /// line at its full width, so the parent can tell when it does not fit.
    /// VoiceOver reads the full name from the zone's label.
    private func teamNameText(lines: Int, minimumScale: CGFloat) -> some View {
        let variants = session.teamNameVariants(for: team)
        let name = variants[min(nameLevel, variants.count - 1)]
        // Half-width zones break a pair at the "&" at every level ("Delon S." /
        // "& Sarah J."), so a longer form is judged by its longer half and can
        // fit in two lines instead of being skipped for needing one.
        let shown = layout == .sideBySide ? name.replacingOccurrences(of: " & ", with: "\n& ") : name
        // The name is the part that gives way: it is never taller than the
        // room left after the score and captions, which keep their size
        // (`layoutPriority(-1)`, and they are not allowed to shrink).
        return Group {
            if wrapsName {
                Text(shown).lineLimit(lines).minimumScaleFactor(minimumScale)
            } else {
                Text(shown)
                    .lineLimit(lines)
                    .minimumScaleFactor(minimumScale)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .layoutPriority(-1)
        .font(.footnote.weight(.semibold))
    }

    /// "Tap for 2nd Server" is too long for a zone at full size: it shrank
    /// while "SERVER 1" on the other zone did not, so the two lines looked
    /// like different sizes. The shorter forms are the same length as
    /// "SERVER 1"; VoiceOver keeps the full hint.
    private var shortCaption: String {
        switch caption {
        // "2nd Server" under the receiving team read as that team being the
        // second server; the arrow says what a tap leads to.
        case "Tap for 2nd Server": "→ Server 2"
        case "Tap for Side Out": "→ Side Out"
        default: caption
        }
    }

    /// Full-width zone: names and caption on the left, the score on the right.
    private var stackedLabel: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                // Players' names can be long ("Mike & Sarah"): the longest
                // form that fits on one line, shrunk a little at the last
                // step, then cut off at the end.
                teamNameText(lines: 1, minimumScale: 0.5)
                // The serving badge says who is up, in words, so the cue is
                // never colour alone; the receiving zone says what a tap
                // does, because it is not a point.
                Text(shortCaption)
                    .font(.caption2.weight(isServing ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                if showsGames {
                    Text("Games \(session.gamesWon(for: team))")
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            // The score is always the same size: a long name gives way to
            // it (a shorter form, then smaller text), never the other way round.
            Text("\(session.score(for: team))")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
    }

    /// Half-width zone, name on top, the score in the middle, then the caption:
    /// the text wraps to two lines because each zone is only about half as wide.
    private var sideBySideLabel: some View {
        VStack(spacing: 2) {
            teamNameText(lines: 2, minimumScale: 0.6)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Text("\(session.score(for: team))")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                // A 52 pt line is about 62 pt tall, most of it empty space
                // above and below the digits. Reserving 46 pt gives that room
                // to the name, so the score and the captions keep their size
                // and a two-line name only has to shrink a little.
                .frame(height: 46)
                .layoutPriority(1)
            Spacer(minLength: 0)
            // Footnote size, a step above the stacked layout's caption2: this
            // is the line that says who serves. An ideal width of 0 keeps the
            // captions out of the "does this form of the name fit" test in
            // `scoreZones`; they scale to the width they are given.
            Text(shortCaption)
                .font(.footnote.weight(isServing ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
            if showsGames {
                Text("Games \(session.gamesWon(for: team))")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
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

/// Two zones of the same width, each half of what is offered. Its ideal width
/// is twice the wider zone's, so a `ViewThatFits` asks "does the wider of the
/// two fit its half?" and not "do the two fit side by side?".
private struct EqualWidthHStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let count = CGFloat(subviews.count)
        let idealWidth = (ideals.map(\.width).max() ?? 0) * count + spacing * max(count - 1, 0)
        return CGSize(
            width: proposal.width ?? idealWidth,
            height: proposal.height ?? ideals.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let count = CGFloat(subviews.count)
        let width = (bounds.width - spacing * (count - 1)) / count
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }
}
