import XCTest
@testable import ServerTwo
import PickleballKit

@MainActor
final class ScoreZoneTextTests: XCTestCase {
    private func caption(
        serving: Bool, sideOut: Bool = true, doubles: Bool = true,
        server: ServerNumber = .one, over: Bool = false
    ) -> String {
        ScoreZoneCaption.text(
            isServing: serving, scoringIsSideOut: sideOut, isDoubles: doubles,
            serverNumber: server, isMatchOver: over
        )
    }

    private func badge(
        serving: Bool, sideOut: Bool = true, doubles: Bool = true,
        server: ServerNumber = .one, over: Bool = false
    ) -> String? {
        ServingBadge.text(
            isServing: serving, scoringIsSideOut: sideOut, isDoubles: doubles,
            serverNumber: server, isMatchOver: over
        )
    }

    // MARK: - Caption

    func testServingTeamInSideOutScoringSaysTapToScore() {
        XCTAssertEqual(caption(serving: true, server: .one), "Tap to Score")
        XCTAssertEqual(caption(serving: true, server: .two), "Tap to Score")
        XCTAssertEqual(caption(serving: true, doubles: false), "Tap to Score")
    }

    func testReceivingCardInDoublesWithServerOneOffersTheSecondServer() {
        XCTAssertEqual(caption(serving: false, server: .one), "Tap for 2nd Server")
    }

    func testReceivingCardInDoublesWithServerTwoOffersASideOut() {
        XCTAssertEqual(caption(serving: false, server: .two), "Tap for Side Out")
    }

    func testReceivingCardInSinglesAlwaysOffersASideOut() {
        XCTAssertEqual(caption(serving: false, doubles: false, server: .one), "Tap for Side Out")
        XCTAssertEqual(caption(serving: false, doubles: false, server: .two), "Tap for Side Out")
    }

    func testRallyScoringSaysTapToScoreOnBothCards() {
        for doubles in [true, false] {
            for server in [ServerNumber.one, .two] {
                XCTAssertEqual(caption(serving: true, sideOut: false, doubles: doubles, server: server), "Tap to Score")
                XCTAssertEqual(caption(serving: false, sideOut: false, doubles: doubles, server: server), "Tap to Score")
            }
        }
    }

    func testMatchOverSaysMatchCompleteOnBothCardsInEveryMode() {
        for serving in [true, false] {
            for sideOut in [true, false] {
                for doubles in [true, false] {
                    XCTAssertEqual(
                        caption(serving: serving, sideOut: sideOut, doubles: doubles, over: true),
                        "Match Complete"
                    )
                }
            }
        }
    }

    // MARK: - Badge

    func testDoublesSideOutBadgeShowsTheServerNumber() {
        XCTAssertEqual(badge(serving: true, server: .one), "SERVER 1")
        XCTAssertEqual(badge(serving: true, server: .two), "SERVER 2")
    }

    func testSinglesAndRallyKeepPlainServing() {
        XCTAssertEqual(badge(serving: true, doubles: false, server: .one), "SERVING")
        XCTAssertEqual(badge(serving: true, sideOut: false, server: .one), "SERVING")
        XCTAssertEqual(badge(serving: true, sideOut: false, doubles: false, server: .two), "SERVING")
    }

    func testReceivingTeamHasNoBadge() {
        XCTAssertNil(badge(serving: false))
        XCTAssertNil(badge(serving: false, doubles: false))
        XCTAssertNil(badge(serving: false, sideOut: false))
    }

    func testNoBadgeOnceTheMatchIsOver() {
        XCTAssertNil(badge(serving: true, over: true))
        XCTAssertNil(badge(serving: true, doubles: false, over: true))
        XCTAssertNil(badge(serving: true, sideOut: false, over: true))
    }

    func testSpokenServerNumberOnlyInDoublesSideOut() {
        XCTAssertEqual(ServingBadge.spokenServerNumber(scoringIsSideOut: true, isDoubles: true, serverNumber: .two), 2)
        XCTAssertNil(ServingBadge.spokenServerNumber(scoringIsSideOut: true, isDoubles: false, serverNumber: .two))
        XCTAssertNil(ServingBadge.spokenServerNumber(scoringIsSideOut: false, isDoubles: true, serverNumber: .one))
    }

    // MARK: - Serve-change haptic (driven by a real match, like ScoringView)

    private func makeMatch() -> PickleballMatch {
        PickleballMatch(
            configuration: GameConfiguration(playMode: .doubles, scoringFormat: .sideOut),
            matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil
        )
    }

    /// Whether the serve-change haptic would fire for `action`.
    private func firesHaptic(_ match: PickleballMatch, _ action: () -> Void) -> Bool {
        let old = AnnouncementSnapshot(match: match)
        action()
        return ServeChangeHaptic.shouldFire(old: old, new: AnnouncementSnapshot(match: match))
    }

    func testHapticFiresOnSecondServerAndOnSideOutButNotOnAScoringMove() {
        let match = makeMatch()   // team A serves as Server 2 (start of game)
        XCTAssertFalse(firesHaptic(match) { match.recordPoint(for: .teamA) }, "a point is the score haptic's job")
        XCTAssertTrue(firesHaptic(match) { match.recordPoint(for: .teamB) }, "Server 2 loses: side out")
        XCTAssertEqual(match.currentGame.state.serverNumber, .one)
        XCTAssertTrue(firesHaptic(match) { match.recordPoint(for: .teamA) }, "Server 1 loses: 2nd server")
        XCTAssertEqual(match.currentGame.state.serverNumber, .two)
    }

    func testHapticIsSilentOnUndoAndOnACorrection() {
        let match = makeMatch()
        match.recordPoint(for: .teamB)   // side out, B serves as Server 1
        XCTAssertFalse(firesHaptic(match) { match.undo() }, "undo restores the serve; it is not a forward move")
        match.recordPoint(for: .teamB)
        XCTAssertFalse(firesHaptic(match) { match.correctScores(teamA: 3, teamB: 2) })
    }

    func testHapticIsSilentOnATimeout() {
        let match = makeMatch()
        XCTAssertFalse(firesHaptic(match) { _ = match.requestTimeout(for: .teamA) })
    }
}
