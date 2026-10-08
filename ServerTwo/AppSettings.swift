import SwiftUI
import Observation

enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Backs its properties with `UserDefaults` manually (via `didSet`) rather
/// than `@AppStorage`, because `@AppStorage` and `@Observable` don't compose
/// on the same stored property — see this plan's Global Constraints.
@Observable
final class AppSettings {
    private enum Keys {
        static let voiceAnnouncerEnabled = "voiceAnnouncerEnabled"
        static let hapticsEnabled = "hapticsEnabled"
        static let theme = "theme"
    }

    private let userDefaults: UserDefaults

    var voiceAnnouncerEnabled: Bool {
        didSet { userDefaults.set(voiceAnnouncerEnabled, forKey: Keys.voiceAnnouncerEnabled) }
    }

    var hapticsEnabled: Bool {
        didSet { userDefaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    var theme: ColorSchemePreference {
        didSet { userDefaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.voiceAnnouncerEnabled = userDefaults.object(forKey: Keys.voiceAnnouncerEnabled) == nil
            ? true
            : userDefaults.bool(forKey: Keys.voiceAnnouncerEnabled)
        self.hapticsEnabled = userDefaults.object(forKey: Keys.hapticsEnabled) == nil
            ? true
            : userDefaults.bool(forKey: Keys.hapticsEnabled)
        self.theme = ColorSchemePreference(rawValue: userDefaults.string(forKey: Keys.theme) ?? "") ?? .system
    }
}
