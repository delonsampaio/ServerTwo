import XCTest
@testable import PickleballKit

final class LastUsedRulesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "LastUsedRulesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testDefaultsToDoublesSingleGameSideOut() {
        let rules = LastUsedRules(userDefaults: makeDefaults())
        XCTAssertEqual(rules.configuration, GameConfiguration())
        XCTAssertEqual(rules.matchFormat, .bestOfOne)
    }

    func testSavedRulesComeBackInANewInstance() {
        let defaults = makeDefaults()
        var rules = LastUsedRules(userDefaults: defaults)
        rules.configuration = GameConfiguration(playMode: .singles, scoringFormat: .rally(freeze: false))
        rules.matchFormat = .bestOfFive
        rules.save()

        let reloaded = LastUsedRules(userDefaults: defaults)
        XCTAssertEqual(reloaded.configuration.playMode, .singles)
        XCTAssertEqual(reloaded.configuration.scoringFormat, .rally(freeze: false))
        XCTAssertEqual(reloaded.matchFormat, .bestOfFive)
    }

    func testCorruptStoredDataFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data([1, 2, 3]), forKey: LastUsedRules.configurationKey)
        defaults.set(99, forKey: LastUsedRules.matchFormatKey)
        let rules = LastUsedRules(userDefaults: defaults)
        XCTAssertEqual(rules.configuration, GameConfiguration())
        XCTAssertEqual(rules.matchFormat, .bestOfOne)
    }
}
