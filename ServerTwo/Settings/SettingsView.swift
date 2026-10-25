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

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            proSection

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
        }
        .navigationTitle("Settings")
        .task { loadMePlayer() }
        .onAppear { storeManager.clearRestoreResult() }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
    }

    /// Always visible, so the purchase (and a restore on a new device) can be
    /// reached without first running into the paywall.
    @ViewBuilder
    private var proSection: some View {
        if activeMatchController.proUnlocked {
            Section(header: Text("Server Two Pro").foregroundStyle(Color.secondaryText)) {
                Label {
                    Text("Server Two Pro: Unlocked")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityIdentifier("Settings.ProUnlocked")
            }
        } else {
            Section(
                header: Text("Server Two Pro").foregroundStyle(Color.secondaryText),
                footer: RestoreResultText(result: storeManager.restoreResult)
            ) {
                Button {
                    isShowingPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(Color.accentColor)
                        // Accent TEXT uses `accentText`, as everywhere else.
                        Text("Unlock Server Two Pro")
                            .foregroundStyle(Color.accentText)
                        Spacer()
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

#Preview {
    NavigationStack {
        SettingsView(onRematch: { _ in })
    }
    .environment(AppSettings())
    .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
    .environment(StoreManager(backend: StoreKitBackend()))
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
