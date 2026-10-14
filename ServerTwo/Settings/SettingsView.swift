import SwiftUI
import SwiftData
import PickleballKit

struct SettingsView: View {
    let onRematch: (RematchRequest) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @State private var mePlayer: SavedPlayer?

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            // Its own section at the top — a core roster/identity feature,
            // not documentation, so it doesn't belong grouped under "Help"
            // alongside a tutorial. Showing the active "Me" player here
            // (when one's set) gives at-a-glance feedback without having
            // to drill in.
            Section("Players") {
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
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("Manage Players")
            }

            Section("Audio & Haptics") {
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

            Section("Appearance") {
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

            Section("Help") {
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
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .task { loadMePlayer() }
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
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
