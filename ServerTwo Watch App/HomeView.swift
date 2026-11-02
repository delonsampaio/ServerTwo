import SwiftUI
import PickleballKit

struct HomeView: View {
    @Binding var rules: LastUsedRules
    @Binding var players: LastUsedPlayers
    let directory: WatchPlayerDirectory
    let access: WatchAccess
    let onStart: () -> Void
    @State private var showingRules = false
    @State private var showingPlayers = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // The system navigation title sits at the leading edge beside
                // the clock; the app name reads better centred on Home.
                Text("Server Two")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                // The rules Start Match will use, so the player sees them
                // without opening the sheet.
                Text(rules.configuration.summaryText(matchFormat: rules.matchFormat))
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("RulesSummary")

                Button(action: onStart) {
                    Text("Start Match")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!access.canStartMatch)
                .accessibilityIdentifier("Start Match")

                // No purchase UI on the watch in v1: the unlock happens on the
                // iPhone and reaches here over WatchConnectivity.
                if !access.canStartMatch {
                    Text("Free demo used. Unlock Server Two Pro on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("DemoUsed")
                }

                playersRow

                Button("Rules") { showingRules = true }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("Rules")
            }
        }
        .sheet(isPresented: $showingRules) {
            RulesSheet(rules: $rules)
        }
        .sheet(isPresented: $showingPlayers) {
            PlayersSheet(lastPlayers: $players, playMode: rules.configuration.playMode, directory: directory)
        }
    }

    /// "Players" and, under it, who is chosen for the next match (nothing when
    /// nobody is). Optional: Start Match works without it.
    private var playersRow: some View {
        let mode = rules.configuration.playMode
        let summary = players.selection.summary(for: mode)
        let chosen = players.selection.matchPlayers(for: mode)
        return Button { showingPlayers = true } label: {
            VStack(spacing: 2) {
                Text("Players")
                // One team a line, each in the longest form that fits, so a
                // long name never spills out of the button.
                if summary != nil {
                    VStack(spacing: 1) {
                        FittingTeamName(variants: chosen.teamNameVariants(for: .teamA), minimumScale: 0.6)
                        FittingTeamName(variants: chosen.teamNameVariants(for: .teamB), prefix: "vs ", minimumScale: 0.6)
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                }
            }
            // Clear of the button's rounded ends, so a long second line does
            // not touch the curve.
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.map { "Players, \($0)" } ?? "Players")
        .accessibilityHint("Choose who plays the next match")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("Players")
    }
}

/// Doubles/singles, scoring format and match length: the three choices a
/// courtside player actually changes. Everything else (target score, win by
/// two, timeouts) keeps the last-used configuration's values, since rich setup
/// lives on the phone. Changes save immediately: there is no Cancel to forget.
struct RulesSheet: View {
    @Binding var rules: LastUsedRules
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WorkoutPreference.key) private var recordsWorkout = true
    @AppStorage(ScoringLayoutPreference.key) private var scoringLayout = ScoringLayout.stacked

    var body: some View {
        NavigationStack {
            Form {
                Picker("Play", selection: $rules.configuration.playMode) {
                    Text("Doubles").tag(PlayMode.doubles)
                    Text("Singles").tag(PlayMode.singles)
                }
                Picker("Scoring", selection: scoringBinding) {
                    Text("Side-out").tag(false)
                    Text("Rally").tag(true)
                }
                Picker("Games", selection: $rules.matchFormat) {
                    Text("Single game").tag(MatchFormat.bestOfOne)
                    Text("Best of 3").tag(MatchFormat.bestOfThree)
                    Text("Best of 5").tag(MatchFormat.bestOfFive)
                }
                // Read when a match starts; a match already under way keeps
                // the workout it began with.
                // Stacked zones are wide and thin; side by side are narrower
                // and taller, a thicker target. Read live by the scoring screen.
                Picker("Layout", selection: $scoringLayout) {
                    Text("Stacked").tag(ScoringLayout.stacked)
                    Text("Side by side").tag(ScoringLayout.sideBySide)
                }
                .accessibilityIdentifier("Scoring Layout")
                Toggle("Record workout", isOn: $recordsWorkout)
                    .accessibilityIdentifier("Record workout")
            }
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: rules.configuration) { rules.save() }
        .onChange(of: rules.matchFormat) { rules.save() }
    }

    /// Rally with the freeze rule off is the only variant offered here; a
    /// phone-configured freeze setting is replaced when the player picks a
    /// scoring format on the watch.
    private var scoringBinding: Binding<Bool> {
        Binding(
            get: { rules.configuration.scoringFormat != .sideOut },
            set: { rules.configuration.scoringFormat = $0 ? .rally(freeze: false) : .sideOut }
        )
    }
}
