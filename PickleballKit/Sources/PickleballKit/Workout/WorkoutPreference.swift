import Foundation

/// The "Record workout" switch in the Watch's Rules sheet. On unless the
/// player turned it off; the views bind to `key` with `@AppStorage`.
public enum WorkoutPreference {
    public static let key = "watchRecordWorkout"

    public static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: key) as? Bool ?? true
    }
}
