import SwiftUI
import PickleballKit

/// What `ScoringView` needs to tell the user mid-match. Plain values only (no
/// model references): a prompt is built at the moment its trigger fires and may
/// sit in a queue until another sheet is dismissed, so it has to describe that
/// moment, not read live match state when it finally appears.
enum ScoringPrompt: Identifiable, Equatable {
    /// `gameIndex` and `direction` let a queued prompt be recognised as stale
    /// (see `isStale`); `threshold` is the score the side switch happens at.
    case sideSwitch(
        gameIndex: Int,
        direction: SideSwitchDirection,
        threshold: Int,
        teamAName: String, teamBName: String,
        teamAScore: Int, teamBScore: Int
    )
    case gameOver(
        gameNumber: Int,
        teamAName: String, teamBName: String,
        teamAScore: Int, teamBScore: Int,
        winner: Team?,
        teamAGames: Int, teamBGames: Int,
        firstServerName: String
    )
    case cancelMatch(
        teamAName: String, teamBName: String,
        teamAScore: Int, teamBScore: Int,
        teamAGames: Int, teamBGames: Int,
        completedGameCount: Int
    )

    /// `switchBack` is the undo/correction case: the engine restores the whole
    /// earlier game state including `hasSideSwitched`, so dropping back under
    /// the threshold puts the teams back on their starting ends.
    enum SideSwitchDirection: Equatable {
        case switchSides
        case switchBack
    }

    /// What (if anything) the user needs telling, given the live
    /// `hasSideSwitched` flag and the value they were last prompted about for
    /// this game. Equal means they already know the current state of the court.
    static func sideSwitchDirection(hasSwitched: Bool, promptedState: Bool) -> SideSwitchDirection? {
        switch (hasSwitched, promptedState) {
        case (true, false): .switchSides
        case (false, true): .switchBack
        default: nil
        }
    }

    /// Whether a change in `completedGames.count` should raise Game Over, and
    /// the acknowledged index to keep. The index must also move DOWN: undoing a
    /// game-ending point and replaying it is a new game ending and should be
    /// announced again, same as a side switch re-crossed after an undo.
    static func gameOverDecision(
        newCompletedCount: Int, acknowledgedIndex: Int, isMatchOver: Bool
    ) -> (shouldPrompt: Bool, acknowledgedIndex: Int) {
        let acknowledged = min(acknowledgedIndex, newCompletedCount - 1)
        guard newCompletedCount > acknowledged + 1, !isMatchOver else { return (false, acknowledged) }
        return (true, newCompletedCount - 1)
    }

    /// A side-switch prompt can sit in the queue behind another sheet; by the
    /// time it would show, the game may have moved on (the same save that
    /// crossed the threshold also finished the game) or the flag may have
    /// flipped again. Showing it then would describe a court state that no
    /// longer exists.
    static func isSideSwitchStale(
        gameIndex: Int, direction: SideSwitchDirection,
        currentGameIndex: Int, hasSideSwitched: Bool
    ) -> Bool {
        gameIndex != currentGameIndex || (direction == .switchSides) != hasSideSwitched
    }

    func isStale(currentGameIndex: Int, hasSideSwitched: Bool) -> Bool {
        guard case let .sideSwitch(gameIndex, direction, _, _, _, _, _) = self else { return false }
        return Self.isSideSwitchStale(
            gameIndex: gameIndex, direction: direction,
            currentGameIndex: currentGameIndex, hasSideSwitched: hasSideSwitched
        )
    }

    var id: String {
        switch self {
        case .sideSwitch: "sideSwitch"
        case .gameOver: "gameOver"
        case .cancelMatch: "cancelMatch"
        }
    }
}

/// Replaces the plain system alerts for Side Switch, Game Over and Cancel
/// Match. Same look as `FinishMatchSheet` (badge, opaque card, full-width
/// glass buttons) so the scoring screen's prompts all read as one family.
struct ScoringPromptSheet: View {
    let prompt: ScoringPrompt
    /// Runs when the user confirms Cancel Match (before the sheet dismisses).
    let onCancelMatch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Today's sizes at the default text size; they scale with Dynamic Type.
    // The digits and the badge stop growing at a cap so the card stays usable.
    @ScaledMetric(relativeTo: .body) private var badgeScale: CGFloat = 1
    @ScaledMetric(relativeTo: .largeTitle) private var scoreDigitSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var dividerHeight: CGFloat = 52
    private let badgeScaleCap: CGFloat = 1.4
    private let scoreDigitSizeCap: CGFloat = 88

    // MARK: Copy (static so the wording is unit-testable)

    /// `gameWinner` is nil for a game the engine doesn't consider won yet
    /// (e.g. rally scoring waiting on a serving-side point), so fall back to
    /// whoever is ahead rather than printing a blank name. nil only on an
    /// exact tie.
    static func resolvedWinner(_ winner: Team?, teamAScore: Int, teamBScore: Int) -> Team? {
        if let winner { return winner }
        if teamAScore == teamBScore { return nil }
        return teamAScore > teamBScore ? .teamA : .teamB
    }

    static func gameOverTitle(
        gameNumber: Int,
        teamAName: String, teamBName: String,
        teamAScore: Int, teamBScore: Int,
        winner: Team?
    ) -> String {
        guard let resolved = resolvedWinner(winner, teamAScore: teamAScore, teamBScore: teamBScore) else { return "Game \(gameNumber) is over" }
        return "Game \(gameNumber) goes to \(resolved == .teamA ? teamAName : teamBName)"
    }

    static func startNextGameTitle(afterGame gameNumber: Int) -> String {
        "Start Game \(gameNumber + 1)"
    }

    static func gamesTallyLine(teamAGames: Int, teamBGames: Int) -> String {
        "Games \(teamAGames) – \(teamBGames)"
    }

    /// Teams change ends (switch sides) after every completed game (Rule 21.F.2;
    /// the rulebook says "change ends", players say "switch sides", and the
    /// app says "switch sides" everywhere). A separate
    /// line, so the existing "Next game starts at 0-0." text element is
    /// unchanged.
    static let switchSidesLine = "Teams switch sides."

    /// Initial service changes every game (Rule 21.F.2), so the first server is
    /// no longer the previous winner and the sheet says who it is. "First
    /// serve: <name>." is grammatical for a singles name, a combined doubles
    /// name and the Team A/Team B fallback.
    static func firstServeLine(name: String) -> String {
        "First serve: \(name)."
    }

    static func sideSwitchScoreLine(
        teamAName: String, teamBName: String, teamAScore: Int, teamBScore: Int
    ) -> String {
        "\(teamAName) \(teamAScore) – \(teamBScore) \(teamBName)"
    }

    static func switchBackBody(threshold: Int) -> String {
        "The score is back under \(threshold), so teams return to their starting ends."
    }

    static func matchupLine(teamAName: String, teamBName: String) -> String {
        "\(teamAName) vs \(teamBName)"
    }

    static func cancelProgressSummary(
        teamAScore: Int, teamBScore: Int,
        teamAGames: Int, teamBGames: Int,
        completedGameCount: Int
    ) -> String {
        guard completedGameCount > 0 else { return "Current game \(teamAScore) – \(teamBScore)" }
        let current = "current game \(teamAScore) – \(teamBScore)"
        return "\(gamesTallyLine(teamAGames: teamAGames, teamBGames: teamBGames)), \(current)"
    }

    // MARK: Body

    var body: some View {
        AdaptiveScroll {
            Group {
                switch prompt {
                case let .sideSwitch(_, direction, threshold, teamAName, teamBName, teamAScore, teamBScore):
                    sideSwitch(
                        direction: direction, threshold: threshold,
                        teamAName: teamAName, teamBName: teamBName,
                        teamAScore: teamAScore, teamBScore: teamBScore
                    )
                case let .gameOver(gameNumber, teamAName, teamBName, teamAScore, teamBScore, winner, teamAGames, teamBGames, firstServerName):
                    gameOver(
                        gameNumber: gameNumber, teamAName: teamAName, teamBName: teamBName,
                        teamAScore: teamAScore, teamBScore: teamBScore, winner: winner,
                        teamAGames: teamAGames, teamBGames: teamBGames,
                        firstServerName: firstServerName
                    )
                case let .cancelMatch(teamAName, teamBName, teamAScore, teamBScore, teamAGames, teamBGames, completedGameCount):
                    cancelMatch(
                        teamAName: teamAName, teamBName: teamBName,
                        teamAScore: teamAScore, teamBScore: teamBScore,
                        teamAGames: teamAGames, teamBGames: teamBGames,
                        completedGameCount: completedGameCount
                    )
                }
            }
        }
        .padding()
        // An opaque elevated surface of our own, same as `FinishMatchSheet`:
        // the sheet's default material is translucent and let the live
        // Scoring screen bleed through behind the card.
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, y: -4)
                .ignoresSafeArea()
        )
        .adaptiveSheetDetents(height: detentHeight)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    private var detentHeight: CGFloat {
        switch prompt {
        case .sideSwitch(_, .switchBack, _, _, _, _, _): 340
        case .sideSwitch: 300
        case .gameOver: 440
        case .cancelMatch: 380
        }
    }

    // MARK: Prompts

    private func sideSwitch(
        direction: ScoringPrompt.SideSwitchDirection, threshold: Int,
        teamAName: String, teamBName: String, teamAScore: Int, teamBScore: Int
    ) -> some View {
        VStack(spacing: 16) {
            switch direction {
            case .switchSides:
                badge(systemName: "arrow.left.arrow.right", tint: Color.accentColor)
                title("Switch Sides")
            case .switchBack:
                badge(systemName: "arrow.uturn.backward", tint: .orange)
                title("Switch Back")
            }
            VStack(spacing: 6) {
                Text(direction == .switchSides
                    ? "Teams swap ends of the court."
                    : Self.switchBackBody(threshold: threshold))
                    .font(.body)
                Text(Self.sideSwitchScoreLine(
                    teamAName: teamAName, teamBName: teamBName,
                    teamAScore: teamAScore, teamBScore: teamBScore
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
            }
            .multilineTextAlignment(.center)
            dismissButton("Got It")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Prompt.SideSwitch")
    }

    private func gameOver(
        gameNumber: Int,
        teamAName: String, teamBName: String,
        teamAScore: Int, teamBScore: Int,
        winner: Team?,
        teamAGames: Int, teamBGames: Int,
        firstServerName: String
    ) -> some View {
        VStack(spacing: 16) {
            badge(systemName: "flag.checkered", tint: Color.accentColor)
            title(Self.gameOverTitle(
                gameNumber: gameNumber, teamAName: teamAName, teamBName: teamBName,
                teamAScore: teamAScore, teamBScore: teamBScore, winner: winner
            ))
            scoreBox(
                teamAName: teamAName, teamBName: teamBName,
                teamAScore: teamAScore, teamBScore: teamBScore,
                winner: Self.resolvedWinner(winner, teamAScore: teamAScore, teamBScore: teamBScore)
            )
            VStack(spacing: 4) {
                Text(Self.gamesTallyLine(teamAGames: teamAGames, teamBGames: teamBGames))
                    .font(.subheadline.weight(.semibold))
                Text(Self.switchSidesLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(Self.firstServeLine(name: firstServerName))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Next game starts at 0-0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            dismissButton(Self.startNextGameTitle(afterGame: gameNumber))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Prompt.GameOver")
    }

    private func cancelMatch(
        teamAName: String, teamBName: String,
        teamAScore: Int, teamBScore: Int,
        teamAGames: Int, teamBGames: Int,
        completedGameCount: Int
    ) -> some View {
        VStack(spacing: 16) {
            badge(systemName: "exclamationmark.triangle.fill", tint: .orange)
            title("Cancel this match?")
            VStack(spacing: 6) {
                Text(Self.matchupLine(teamAName: teamAName, teamBName: teamBName))
                    .font(.body.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                Text(Self.cancelProgressSummary(
                    teamAScore: teamAScore, teamBScore: teamBScore,
                    teamAGames: teamAGames, teamBGames: teamBGames,
                    completedGameCount: completedGameCount
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text("This can't be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            // Stacked, not side by side: "Cancel Match" is long enough that
            // two equal columns would crowd it, and the destructive action
            // should be a deliberate reach rather than a neighbor of the
            // safe one.
            VStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    buttonLabel("Keep Playing")
                }
                .buttonStyle(.glassProminent)
                .tint(Color.accentColor)
                .accessibilityIdentifier("Prompt.KeepPlaying")

                Button(role: .destructive) {
                    onCancelMatch()
                    dismiss()
                } label: {
                    buttonLabel("Cancel Match")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.glass)
                .tint(.red)
                .accessibilityIdentifier("Confirm Cancel Match")
            }
            .controlSize(.large)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Prompt.CancelMatch")
    }

    // MARK: Shared pieces

    private func badge(systemName: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
                .overlay(Circle().strokeBorder(tint.opacity(0.3), lineWidth: 1))
                .frame(width: 60 * min(badgeScale, badgeScaleCap), height: 60 * min(badgeScale, badgeScaleCap))
            Image(systemName: systemName)
                .font(.system(size: 28 * min(badgeScale, badgeScaleCap), weight: .bold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
            .accessibilityAddTraits(.isHeader)
    }

    private func buttonLabel(_ text: String) -> some View {
        // `.frame(maxWidth: .infinity)` on the label, not the Button — on the
        // Button it only widens the tap target and leaves the glass
        // background hugging the text (same note as `FinishMatchSheet`).
        Text(text)
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private func dismissButton(_ text: String) -> some View {
        Button {
            dismiss()
        } label: {
            buttonLabel(text)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.accentColor)
        .controlSize(.large)
        .accessibilityIdentifier("Prompt.Dismiss")
    }

    /// The finished game's final score, in `FinishMatchSheet`'s inset-box
    /// style, with the winner emphasized.
    private func scoreBox(
        teamAName: String, teamBName: String,
        teamAScore: Int, teamBScore: Int,
        winner: Team?
    ) -> some View {
        HStack(spacing: 0) {
            scoreColumn(name: teamAName, value: teamAScore, highlighted: winner == .teamA)
            Rectangle()
                .fill(.primary.opacity(0.12))
                .frame(width: 1, height: dividerHeight)
            scoreColumn(name: teamBName, value: teamBScore, highlighted: winner == .teamB)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func scoreColumn(name: String, value: Int, highlighted: Bool) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: min(scoreDigitSize, scoreDigitSizeCap), weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(highlighted ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Game Over") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ScoringPromptSheet(
            prompt: .gameOver(
                gameNumber: 1, teamAName: "Delon", teamBName: "Fred",
                teamAScore: 11, teamBScore: 6, winner: .teamA,
                teamAGames: 1, teamBGames: 0,
                firstServerName: "Fred"
            ),
            onCancelMatch: {}
        )
    }
}

#Preview("Side Switch") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ScoringPromptSheet(
            prompt: .sideSwitch(
                gameIndex: 0, direction: .switchSides, threshold: 6,
                teamAName: "Delon", teamBName: "Fred", teamAScore: 6, teamBScore: 3
            ),
            onCancelMatch: {}
        )
    }
}

#Preview("Cancel Match") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ScoringPromptSheet(
            prompt: .cancelMatch(
                teamAName: "Delon", teamBName: "Fred",
                teamAScore: 3, teamBScore: 2, teamAGames: 1, teamBGames: 0,
                completedGameCount: 1
            ),
            onCancelMatch: {}
        )
    }
}
