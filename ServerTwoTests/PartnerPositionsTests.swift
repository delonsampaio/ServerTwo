import XCTest
@testable import ServerTwo

@MainActor
final class PartnerPositionsTests: XCTestCase {
    private func make(_ name: String, _ score: Int, swapped: Bool = false) -> PartnerPositions? {
        PartnerPositions.make(teamName: name, score: score, swapped: swapped)
    }

    func testEvenScorePutsPlayerOneOnTheRight() throws {
        let positions = try XCTUnwrap(make("Delon & Katie", 0))
        XCTAssertEqual(positions.player1Name, "Delon")
        XCTAssertEqual(positions.player1Side, .right)
        XCTAssertEqual(positions.player2Name, "Katie")
        XCTAssertEqual(positions.player2Side, .left)
        XCTAssertEqual(make("Delon & Katie", 8)?.player1Side, .right)
    }

    func testOddScorePutsPlayerOneOnTheLeft() throws {
        let positions = try XCTUnwrap(make("Delon & Katie", 1))
        XCTAssertEqual(positions.player1Side, .left)
        XCTAssertEqual(positions.player2Side, .right)
        XCTAssertEqual(make("Delon & Katie", 7)?.player1Side, .left)
    }

    func testSwappedFlagInvertsBothParities() {
        XCTAssertEqual(make("Delon & Katie", 0, swapped: true)?.player1Side, .left)
        XCTAssertEqual(make("Delon & Katie", 1, swapped: true)?.player1Side, .right)
        XCTAssertEqual(make("Delon & Katie", 0, swapped: true)?.player2Side, .right)
    }

    func testPartnersAreAlwaysOnOppositeSides() {
        for score in 0...25 {
            for swapped in [false, true] {
                let p = make("A & B", score, swapped: swapped)
                XCTAssertNotNil(p)
                XCTAssertNotEqual(p?.player1Side, p?.player2Side)
            }
        }
    }

    func testLargeScoresStillFollowParity() {
        XCTAssertEqual(make("A & B", 1_000_000)?.player1Side, .right)
        XCTAssertEqual(make("A & B", 1_000_001)?.player1Side, .left)
    }

    func testNamesAreTrimmed() {
        let positions = make("  Delon  &   Katie ", 0)
        XCTAssertEqual(positions?.player1Name, "Delon")
        XCTAssertEqual(positions?.player2Name, "Katie")
    }

    func testNoSeparatorMeansNoPositions() {
        XCTAssertNil(make("Team A", 0))
        XCTAssertNil(make("Delon", 3))
        XCTAssertNil(make("", 0))
    }

    func testABlankPartIsRejected() {
        XCTAssertNil(make(" & Katie", 0))
        XCTAssertNil(make("Delon & ", 0))
        XCTAssertNil(make("Delon &  & Katie", 0))
        XCTAssertNil(make(" & ", 0))
    }

    func testMoreThanTwoPartsIsRejected() {
        XCTAssertNil(make("A & B & C", 0))
    }

    func testAmpersandWithoutSpacesStaysInsideAName() {
        let positions = make("AT&T Fan & Katie", 0)
        XCTAssertEqual(positions?.player1Name, "AT&T Fan")
        XCTAssertEqual(positions?.player2Name, "Katie")
        XCTAssertNil(make("Delon&Katie", 0))
    }

    func testBadgesAndSpokenAndPreviewText() throws {
        XCTAssertEqual(PartnerPositions.Side.right.badge, "R")
        XCTAssertEqual(PartnerPositions.Side.left.badge, "L")
        let even = try XCTUnwrap(make("Delon & Katie", 2))
        XCTAssertEqual(even.spokenSummary, "Delon on the right, Katie on the left")
        XCTAssertEqual(even.previewText, "Delon R · Katie L")
        let odd = try XCTUnwrap(make("Delon & Katie", 3))
        XCTAssertEqual(odd.spokenSummary, "Katie on the right, Delon on the left")
        XCTAssertEqual(odd.previewText, "Delon L · Katie R")
    }
}
