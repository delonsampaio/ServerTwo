import XCTest
@testable import PickleballKit

final class ScoringLayoutPreferenceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "ScoringLayoutPreferenceTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsToStacked() {
        XCTAssertEqual(ScoringLayoutPreference.current(userDefaults: makeDefaults()), .stacked)
    }

    func testRemembersSideBySide() {
        let defaults = makeDefaults()
        defaults.set(ScoringLayout.sideBySide.rawValue, forKey: ScoringLayoutPreference.key)
        XCTAssertEqual(ScoringLayoutPreference.current(userDefaults: defaults), .sideBySide)
    }

    func testAnUnknownStoredValueFallsBackToStacked() {
        let defaults = makeDefaults()
        defaults.set("diagonal", forKey: ScoringLayoutPreference.key)
        XCTAssertEqual(ScoringLayoutPreference.current(userDefaults: defaults), .stacked)
    }
}
