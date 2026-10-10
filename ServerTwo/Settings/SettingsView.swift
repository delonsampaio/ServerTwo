import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings
        Form {
            Section("Audio & Haptics") {
                Toggle("Voice Announcer", isOn: $appSettings.voiceAnnouncerEnabled)
                Toggle("Haptics", isOn: $appSettings.hapticsEnabled)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appSettings.theme) {
                    ForEach(ColorSchemePreference.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }

            Section("Help") {
                NavigationLink("How to Play Pickleball") {
                    HowToPlayView()
                }
                NavigationLink("Manage Players") {
                    ManagePlayersView()
                }
                .accessibilityIdentifier("Manage Players")
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
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppSettings())
}
