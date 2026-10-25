import XCTest
@testable import ServerTwo

@MainActor
final class AccessibilityTextTests: XCTestCase {
    func testScoreZoneLabelStartsWithNameAndPoints() {
        let idle = AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: false, serverNumber: nil)
        let serving = AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true, serverNumber: nil)
        XCTAssertEqual(idle, "Delon, 12 points")
        XCTAssertEqual(serving, "Delon, 12 points, serving")
        XCTAssertTrue(idle.hasPrefix("Delon, 12 points"))
        XCTAssertTrue(serving.hasPrefix("Delon, 12 points"))
    }

    func testScoreZoneLabelSaysTheServerNumberForTheServingTeamOnly() {
        XCTAssertEqual(
            AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true, serverNumber: 1),
            "Delon, 12 points, serving, server 1"
        )
        XCTAssertEqual(
            AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true, serverNumber: 2),
            "Delon, 12 points, serving, server 2"
        )
        // A receiving team never mentions a server, even if a number is passed.
        XCTAssertEqual(
            AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: false, serverNumber: 2),
            "Delon, 12 points"
        )
    }

    func testScoreZoneLabelLeavesTheDigitsParseableAfterTheFirstComma() {
        // The same parsing ScoreZoneGestureUITests uses on the zone's label.
        func score(of label: String) -> Int {
            guard let comma = label.range(of: ", ") else { return -1 }
            let digits = label[comma.upperBound...].prefix(while: \.isNumber)
            return Int(digits) ?? -1
        }
        XCTAssertEqual(score(of: AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: false, serverNumber: nil)), 12)
        XCTAssertEqual(score(of: AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true, serverNumber: nil)), 12)
        XCTAssertEqual(score(of: AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true, serverNumber: 2)), 12)
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
            AccessibilityText.pointRowLabel(sequence: 3, scorerName: "Team A", scoreAfter: "4 to 2"),
            "Point 3, Team A scored, 4 to 2"
        )
    }
}
