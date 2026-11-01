import Foundation

/// How the Watch scoring screen arranges the two tap zones. Stacked gives each
/// zone the full width (room for names and big scores); side by side gives
/// each zone more height (a thicker target).
public enum ScoringLayout: String, CaseIterable, Sendable {
    case stacked
    case sideBySide
}

/// The "Layout" picker in the Watch's Rules sheet; the views bind to `key`
/// with `@AppStorage`. Stacked unless the player chose otherwise.
public enum ScoringLayoutPreference {
    public static let key = "watchScoringLayout"

    public static func current(userDefaults: UserDefaults = .standard) -> ScoringLayout {
        userDefaults.string(forKey: key).flatMap(ScoringLayout.init(rawValue:)) ?? .stacked
    }
}
