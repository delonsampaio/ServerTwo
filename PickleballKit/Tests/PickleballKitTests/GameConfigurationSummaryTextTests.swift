import XCTest
@testable import PickleballKit

final class GameConfigurationSummaryTextTests: XCTestCase {
    func testSummaryNamesTheModeAndBestOf() {
        XCTAssertEqual(GameConfiguration(playMode: .doubles).summaryText(matchFormat: .bestOfThree), "Doubles • Best of 3")
        XCTAssertEqual(GameConfiguration(playMode: .singles).summaryText(matchFormat: .bestOfOne), "Singles • Best of 1")
    }

    func testRallyScoringIsNotedWithOrWithoutFreeze() {
        for freeze in [false, true] {
            let config = GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: freeze))
            XCTAssertEqual(config.summaryText(matchFormat: .bestOfFive), "Doubles • Best of 5 • Rally")
        }
    }
}
