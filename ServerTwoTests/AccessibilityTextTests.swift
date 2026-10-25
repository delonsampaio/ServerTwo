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

    func testScoreZoneLabelAppendsThePartnerPositionsLast() throws {
        let even = try XCTUnwrap(PartnerPositions.make(teamName: "Delon & Katie", score: 2, swapped: false))
        let odd = try XCTUnwrap(PartnerPositions.make(teamName: "Delon & Katie", score: 3, swapped: false))
        XCTAssertEqual(
            AccessibilityText.scoreZoneLabel(name: "Delon & Katie", score: 2, isServing: false, serverNumber: nil, positions: even),
            "Delon & Katie, 2 points, Delon on the right, Katie on the left"
        )
        XCTAssertEqual(
            AccessibilityText.scoreZoneLabel(name: "Delon & Katie", score: 3, isServing: true, serverNumber: 2, positions: odd),
            "Delon & Katie, 3 points, serving, server 2, Katie on the right, Delon on the left"
        )
        let swapped = try XCTUnwrap(PartnerPositions.make(teamName: "Delon & Katie", score: 2, swapped: true))
        XCTAssertEqual(
            AccessibilityText.scoreZoneLabel(name: "Delon & Katie", score: 2, isServing: true, serverNumber: nil, positions: swapped),
            "Delon & Katie, 2 points, serving, Katie on the right, Delon on the left"
        )
    }

    func testScoreZoneLabelWithoutPositionsIsUnchanged() {
        XCTAssertEqual(
            AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true, serverNumber: 1, positions: nil),
            AccessibilityText.scoreZoneLabel(name: "Delon", score: 12, isServing: true, serverNumber: 1)
        )
    }

    func testScoreZoneLabelWithPositionsStaysParseable() throws {
        let positions = try XCTUnwrap(PartnerPositions.make(teamName: "Delon & Katie", score: 12, swapped: false))
        let label = AccessibilityText.scoreZoneLabel(name: "Delon & Katie", score: 12, isServing: true, serverNumber: 1, positions: positions)
        let comma = try XCTUnwrap(label.range(of: ", "))
        XCTAssertEqual(Int(label[comma.upperBound...].prefix(while: \.isNumber)), 12)
        XCTAssertTrue(label.contains("12 points"))
    }

    func testScoreZoneHintMentionsTheSwapOnlyWhenPositionsAreShown() {
        XCTAssertEqual(
            AccessibilityText.scoreZoneHintWithPositions,
            "Double tap to score a point. Use the Actions rotor to correct the score or swap partner positions."
        )
        XCTAssertFalse(AccessibilityText.scoreZoneHint.contains("swap"))
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
