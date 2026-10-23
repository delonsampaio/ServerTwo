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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let setup: PendingMatchSetup

    // The coin (120 pt, with 48 pt / 44 pt glyphs) scales with Dynamic Type up
    // to 1.4x.
    @ScaledMetric(relativeTo: .largeTitle) private var coinScale: CGFloat = 1
    private let coinScaleCap: CGFloat = 1.4
    /// Never below 1: `@ScaledMetric` also scales down below the default size.
    private var coinFactor: CGFloat { max(1, min(coinScale, coinScaleCap)) }

    @State private var isFlipping = false
    /// `flip()` settles 0.7 s later. If the screen was dismissed meanwhile
    /// (Cancel), that late settle must neither set state nor announce
    /// "<name> serves first" over whatever screen is showing now.
    @State private var isOnScreen = true
    @State private var coinRotation: Double = 0
    @State private var result: Team?
    /// Which team's letter the coin currently shows — `nil` before the
    /// first flip starts, so the coin reads as genuinely undecided (a
    /// neutral icon) instead of silently pre-displaying Team A's letter,
    /// which looked like Team A had already been chosen before anyone
    /// touched anything. A flat SwiftUI view rotated in 3D has no true
    /// "back face" to reveal mid-spin — once flipping starts, this fakes a
    /// real flip by swapping the displayed letter a few times while
    /// `coinRotation` animates, landing on the actual outcome exactly when
    /// the spin stops.
    @State private var displayedTeam: Team?
    // Moves VoiceOver to "Begin Match" once a result exists. Set from the
    // button's `onAppear`, not from `settle(on:)`: the button is inserted by
    // the same state change and is not in the accessibility tree yet.
    @AccessibilityFocusState private var beginMatchFocused: Bool

    var body: some View {
        AdaptiveScroll {
            VStack(spacing: 32) {
                Spacer()

                // Matchup, coin, and the flip action are one visual group —
                // tight internal spacing keeps them reading as a single block
                // rather than floating independently at their own heights.
                VStack(spacing: 20) {
                    Text("\(setup.resolvedTeamAName) vs \(setup.resolvedTeamBName)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    coin

                    // Always present (reserving its line's height) and only
                    // its content/opacity changes — if the result line were
                    // added via `if let`, the extra line appearing only once a
                    // result exists would change this VStack's content height,
                    // and with Spacers above and below, SwiftUI would
                    // redistribute space between them and visibly shift
                    // everything else when the coin lands.
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(result == nil ? .secondary : .primary)
                        .accessibilityIdentifier("FirstServeResult")

                    if let result {
                        Button("Begin Match") {
                            activeMatchController.confirmFirstServe(result)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("Begin Match")
                        .accessibilityFocused($beginMatchFocused)
                        .onAppear { beginMatchFocused = true }
                    } else {
                        Button("Flip Coin") {
                            flip()
                        }
                        .font(.headline.weight(.semibold))
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                        .disabled(isFlipping)
                        .accessibilityIdentifier("Flip Coin")
                    }
                }

                Spacer()

                // Grounded in its own card instead of floating bare text and
                // buttons directly against the screen background.
                VStack(spacing: 12) {
                    Text("Already spun a paddle?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    AdaptiveStack(spacing: 12) {
                        // `.frame(maxWidth: .infinity)` on the label (not the
                        // Button itself) — applied to the Button directly it
                        // only widened the tap area, while the visible
                        // `.bordered` background kept hugging the text, still
                        // leaving a gap between two unequal-looking pills.
                        Button {
                            settle(on: .teamA)
                        } label: {
                            Text("\(setup.resolvedTeamAName) Won Spin")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("Team A Won Spin")
                        Button {
                            settle(on: .teamB)
                        } label: {
                            Text("\(setup.resolvedTeamBName) Won Spin")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("Team B Won Spin")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding()
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .navigationTitle("First Serve")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            // Matches "Cancel Match"'s top-leading placement on the live
            // Scoring screen right after this one in the same flow — it
            // previously sat at the very bottom, right above the tab bar,
            // where a stray thumb tap mid-scroll could abort setup, and
            // its placement didn't match the very next screen's.
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", role: .cancel) {
                    activeMatchController.cancelPendingMatch()
                }
                .accessibilityIdentifier("Cancel Coin Flip")
            }
        }
    }

    private var subtitle: String {
        guard let displayedTeam else { return "Decide who serves first" }
        let name = displayedTeam == .teamA ? setup.resolvedTeamAName : setup.resolvedTeamBName
        return result == nil ? name : "\(name) serves first"
    }

    private var coin: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 4))
                .overlay(Circle().inset(by: 8).strokeBorder(.white.opacity(0.15), lineWidth: 1.5))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 16, y: 6)
                .frame(width: 120 * coinFactor, height: 120 * coinFactor)
            // A neutral icon (not a team letter) before the first flip —
            // showing a letter from the very start made the coin look
            // identical to a `PlayerAvatarView` with that team already
            // pre-selected, before anyone had flipped anything.
            if let displayedTeam {
                Text(letter(for: displayedTeam))
                    .font(.system(size: 48 * coinFactor, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "figure.pickleball")
                    .font(.system(size: 44 * coinFactor, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .rotation3DEffect(.degrees(coinRotation), axis: (x: 0, y: 1, z: 0))
        // Decorative: the result is spoken through the "serves first" line.
        .accessibilityHidden(true)
        .sensoryFeedback(.impact, trigger: result) { oldValue, newValue in
            newValue != nil
        }
    }

    private func letter(for team: Team) -> String {
        let name = team == .teamA ? setup.resolvedTeamAName : setup.resolvedTeamBName
        return String(name.prefix(1)).uppercased()
    }

    private func flip() {
        let plan = CoinFlipAnimationPlan.plan(reduceMotion: reduceMotion)
        let outcome = CoinFlip.flip()
        // Reduce Motion: no spin, no letter toggling, no delay. `isFlipping`
        // is never set, so it cannot be left stuck.
        guard plan.spins else {
            settle(on: outcome)
            return
        }
        isFlipping = true
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
        for step in 0..<plan.letterToggles {
            DispatchQueue.main.asyncAfter(deadline: .now() + toggleInterval * Double(step)) {
                displayedTeam = displayedTeam == .teamA ? .teamB : .teamA
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + plan.settleDelay) {
            guard isOnScreen else { return }
            isFlipping = false
            settle(on: outcome)
        }
    }

    private func settle(on team: Team) {
        result = team
        displayedTeam = team
        let name = team == .teamA ? setup.resolvedTeamAName : setup.resolvedTeamBName
        VoiceOverAnnouncement.post("\(name) serves first")
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
