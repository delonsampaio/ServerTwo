import XCTest
@testable import ServerTwo

@MainActor
final class AccessibilityTextTests: XCTestCase {
    func testScoreZoneLabelStartsWithNameAndPoints() {
        let idle = AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: false)
        let serving = AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true)
        XCTAssertEqual(idle, "Delon, 12 points")
        XCTAssertEqual(serving, "Delon, 12 points, serving")
        XCTAssertTrue(idle.hasPrefix("Delon, 12 points"))
        XCTAssertTrue(serving.hasPrefix("Delon, 12 points"))
    }

    func testScoreZoneLabelLeavesTheDigitsParseableAfterTheFirstComma() {
        // The same parsing ScoreZoneGestureUITests uses on the zone's label.
        func score(of label: String) -> Int {
            guard let comma = label.range(of: ", ") else { return -1 }
            let digits = label[comma.upperBound...].prefix(while: \.isNumber)
            return Int(digits) ?? -1
        }
        XCTAssertEqual(score(of: AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: false)), 12)
        XCTAssertEqual(score(of: AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true)), 12)
    }

    func testScoreZoneHint() {
        XCTAssertEqual(
            AccessibilityText.scoreZoneHint,
            "Double tap to score a point. Use the Actions rotor to correct the score."
        )
    }

    func testResultWords() {
        XCTAssertEqual(AccessibilityText.resultWord(didWin: true), "Won")
        XCTAssertEqual(AccessibilityText.resultWord(didWin: false), "Lost")
    }

    func testRecentFormValueKeepsTheGivenOrder() {
        XCTAssertEqual(AccessibilityText.recentFormValue([true, false, true]), "Won, Lost, Won")
        XCTAssertEqual(AccessibilityText.recentFormValue([false, false, true]), "Lost, Lost, Won")
    }

    func testEmptyRecentFormIsAnEmptyString() {
        XCTAssertEqual(AccessibilityText.recentFormValue([]), "")
    }

    func testPointRowLabel() {
        XCTAssertEqual(
            AccessibilityText.pointRowLabel(sequence: 3, scorerName: "Team A", scoreAfter: "4-2"),
            "Point 3, Team A scored, 4-2"
        )
    }
}
