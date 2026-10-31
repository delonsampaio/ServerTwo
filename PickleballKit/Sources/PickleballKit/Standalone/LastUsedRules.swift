import Foundation

/// The rules the Watch's "Start Match" button uses: whatever was played last.
/// Kept in the kit (not the watch target) so the load/save/fallback behaviour
/// is unit-tested with the rest of the logic.
public struct LastUsedRules {
    public static let configurationKey = "watchLastUsedConfiguration"
    public static let matchFormatKey = "watchLastUsedMatchFormat"

    public var configuration: GameConfiguration
    public var matchFormat: MatchFormat

    private let userDefaults: UserDefaults

    /// Unreadable or missing data falls back to the app's usual defaults
    /// (doubles, one game to 11, side-out) rather than failing the launch.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.configuration = userDefaults.data(forKey: Self.configurationKey)
            .flatMap { try? JSONDecoder().decode(GameConfiguration.self, from: $0) }
            ?? GameConfiguration()
        self.matchFormat = MatchFormat(rawValue: userDefaults.integer(forKey: Self.matchFormatKey)) ?? .bestOfOne
    }

    public func save() {
        if let data = try? JSONEncoder().encode(configuration) {
            userDefaults.set(data, forKey: Self.configurationKey)
        }
        userDefaults.set(matchFormat.rawValue, forKey: Self.matchFormatKey)
    }
}
