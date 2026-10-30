import SwiftUI
import SwiftData
import PickleballKit

struct SettingsView: View {
    let onRematch: (RematchRequest) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @Environment(ActiveMatchController.self) private var activeMatchController
    @Environment(StoreManager.self) private var storeManager
    @State private var mePlayer: SavedPlayer?
    @State private var isShowingPaywall = false

    private static let liveActivityCaption = "Shows the live score on the Lock Screen and in the Dynamic Island while a match is running. Turn off to keep scoring private to the app. iOS may also limit Live Activities in Settings > Server Two."

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            // While locked the purchase stays the first thing in Settings, one
            // tap from a new user or App Review. Once unlocked it is only a
            // status, so it moves below the real settings (see the end of
            // this Form) instead of taking the top of the list.
            if !activeMatchController.proUnlocked {
                proSection
            }

            // Its own section at the top — a core roster/identity feature,
            // not documentation, so it doesn't belong grouped under "Help"
            // alongside a tutorial. Showing the active "Me" player here
            // (when one's set) gives at-a-glance feedback without having
            // to drill in.
            Section(header: Text("Players").foregroundStyle(Color.secondaryText)) {
                NavigationLink {
                    ManagePlayersView(onRematch: onRematch)
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Manage Players")
                        Spacer()
                        if let mePlayer {
                            Text(mePlayer.name)
                                .font(.subheadline)
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }
                .accessibilityIdentifier("Manage Players")
            }

            Section(header: Text("Audio & Haptics").foregroundStyle(Color.secondaryText)) {
                Label {
                    Toggle("Voice Announcer", isOn: $appSettings.voiceAnnouncerEnabled)
                } icon: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.accentColor)
                }
                Label {
                    Toggle("Haptics", isOn: $appSettings.hapticsEnabled)
                } icon: {
                    Image(systemName: "water.waves")
                        .foregroundStyle(Color.accentColor)
                }
            }

            // Its own section (not a row of the one above) so its explanation
            // is a real section footer: a footer in the shared section would
            // read as being about Voice Announcer and Haptics too, and a
            // caption squeezed under the switch inside the row sat flush
            // against it. Footers wrap at any text size.
            Section(
                footer: Text(Self.liveActivityCaption)
                    .foregroundStyle(Color.secondaryText)
                    // Spoken once, as the switch's hint.
                    .accessibilityHidden(true)
            ) {
                Label {
                    Toggle("Live Activity", isOn: $appSettings.liveActivityEnabled)
                        .accessibilityHint(Self.liveActivityCaption)
                        .accessibilityIdentifier("Settings.LiveActivityToggle")
                } icon: {
                    Image(systemName: "platter.filled.top.iphone")
                        .foregroundStyle(Color.accentColor)
                }
            }

            Section(header: Text("Appearance").foregroundStyle(Color.secondaryText)) {
                Label {
                    Picker("Theme", selection: $appSettings.theme) {
                        ForEach(ColorSchemePreference.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                } icon: {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(Color.accentColor)
                }
            }

            Section(header: Text("Help").foregroundStyle(Color.secondaryText)) {
                NavigationLink {
                    HowToPlayView()
                } label: {
                    Label {
                        Text("How to Play Pickleball")
                    } icon: {
                        Image(systemName: "book.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(Color.secondaryText)
                }
            }

            // Exactly one of these two placements is ever active, and both
            // render the same section, so a change of entitlement while
            // Settings is open just moves it instead of duplicating it.
            // `proUnlocked` is seeded from a cache at launch, so a paying
            // user never sees it appear on top and then jump.
            if activeMatchController.proUnlocked {
                proSection
            }
        }
        .navigationTitle("Settings")
        .task { loadMePlayer() }
        .onAppear { storeManager.clearRestoreResult() }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
    }

    /// Always present, so the purchase (and a restore on a new device) can be
    /// reached without first running into the paywall. Once unlocked it is only
    /// a status: there is nothing to restore, and if an entitlement is ever
    /// revoked the app flips to locked and the Unlock + Restore rows come back
    /// on top. Where it sits (top while locked, bottom once unlocked) is
    /// decided by the caller.
    @ViewBuilder
    private var proSection: some View {
        Section(
            header: Text("Server Two Pro").foregroundStyle(Color.secondaryText),
            footer: RestoreResultText(result: storeManager.restoreResult)
        ) {
            if activeMatchController.proUnlocked {
                Label {
                    Text("Server Two Pro: Unlocked")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityIdentifier("Settings.ProUnlocked")
            } else {
                Button {
                    isShowingPaywall = true
                } label: {
                    // Stacks the price under the title at accessibility sizes.
                    AdaptiveStack(rowAlignment: .firstTextBaseline, columnAlignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.open.fill")
                                .foregroundStyle(Color.accentColor)
                            // Accent TEXT uses `accentText`, as everywhere else.
                            Text("Unlock Server Two Pro")
                                .foregroundStyle(Color.accentText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let price = storeManager.displayPrice {
                            Text(price)
                                .font(.subheadline)
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }
                .accessibilityIdentifier("Settings.UnlockPro")

                Button {
                    Task { await storeManager.restorePurchases() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.accentColor)
                        Text("Restore Purchases")
                            .foregroundStyle(Color.accentText)
                    }
                }
                .disabled(storeManager.isRestoring)
                .accessibilityIdentifier("Settings.Restore")
            }
        }
    }

    private func loadMePlayer() {
        let repository = MatchRepository(modelContext: modelContext)
        mePlayer = try? repository.fetchMePlayer()
    }
}

// Debug only: the preview store is the debug fake, which Release builds do not contain.
#if DEBUG
#Preview {
    NavigationStack {
        SettingsView(onRematch: { _ in })
    }
    .environment(AppSettings())
    .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
    .environment(StoreManager.preview)
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
#endif
