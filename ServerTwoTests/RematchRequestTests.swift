import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

final class RematchRequestTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    /// Reproduces a real bug report: rematching a match whose `TeamSide`s
    /// have no linked `SavedPlayer`s (e.g. an older match from before
    /// player-linking existed, or any path that saved without players)
    /// left every field looking exactly like freshly-typed, unselected
    /// text — because every slot's `savedPlayerID` comes back nil, and
    /// `MatchSetupView` can't tell that apart from "the user just typed
    /// this." This test pins the actual cause: `RematchRequest` for a
    /// match saved with no player links.
    func testRematchRequestHasNoSavedPlayerIDsWhenTheMatchHasNoLinkedPlayers() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        // Saved WITHOUT teamAPlayers/teamBPlayers (defaults to []) - this
        // is exactly what a match saved with no player linkage looks like.
        let record = try repository.saveCompletedMatch(
            match,
            teamAName: "Delon & Katie",
            teamBName: "Yi & Fred",
            startedAt: Date()
        )

        let request = try XCTUnwrap(RematchRequest(match: record))

        XCTAssertNil(request.teamAPlayer1.savedPlayerID, "Team A Player 1 should have no id to carry over")
        XCTAssertNil(request.teamAPlayer2?.savedPlayerID, "Team A Player 2 should have no id to carry over")
        XCTAssertNil(request.teamBPlayer1.savedPlayerID, "Team B Player 1 should have no id to carry over")
        XCTAssertNil(request.teamBPlayer2?.savedPlayerID, "Team B Player 2 should have no id to carry over")

        // The names themselves should still split correctly from the
        // combined display name, even without ids.
        XCTAssertEqual(request.teamAPlayer1.name, "Delon")
        XCTAssertEqual(request.teamAPlayer2?.name, "Katie")
        XCTAssertEqual(request.teamBPlayer1.name, "Yi")
        XCTAssertEqual(request.teamBPlayer2?.name, "Fred")
    }

    /// Contrast case: a match WITH properly linked players should carry
    /// real ids through, so Rematch-prefilled fields correctly suppress
    /// their suggestion chips (the behavior this bug report expected).
    func testRematchRequestCarriesSavedPlayerIDsWhenTheMatchHasLinkedPlayers() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let delon = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
        let katie = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Katie"))
        let yi = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Yi"))
        let fred = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Fred"))

        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        let record = try repository.saveCompletedMatch(
            match,
            teamAName: "Delon & Katie",
            teamBName: "Yi & Fred",
            startedAt: Date(),
            teamAPlayers: [delon, katie],
            teamBPlayers: [yi, fred]
        )

        let request = try XCTUnwrap(RematchRequest(match: record))

        XCTAssertNotNil(request.teamAPlayer1.savedPlayerID)
        XCTAssertNotNil(request.teamAPlayer2?.savedPlayerID)
        XCTAssertNotNil(request.teamBPlayer1.savedPlayerID)
        XCTAssertNotNil(request.teamBPlayer2?.savedPlayerID)
    }

    /// Pins the fix for the bug above: `MatchSetupView.applyRematch` must
    /// not leave a nil id sitting next to Rematch-prefilled text (that's
    /// what made the fields look freshly typed). For any slot with no
    /// `savedPlayerID`, it resolves one immediately via the same
    /// `upsertSavedPlayer` call `startMatch()` would otherwise defer to -
    /// reusing an existing player by name rather than leaving the id
    /// unresolved.
    func testUnlinkedRematchSlotResolvesToAnExistingSavedPlayerByName() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        // "Delon" already exists as a SavedPlayer from some earlier,
        // properly-linked match - this is the common real-world case: the
        // specific match being rematched just happens not to have linked
        // players, even though the person has played (and saved) before.
        let delon = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))

        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        let record = try repository.saveCompletedMatch(
            match,
            teamAName: "Delon & Katie",
            teamBName: "Yi & Fred",
            startedAt: Date()
        )

        let request = try XCTUnwrap(RematchRequest(match: record))
        XCTAssertNil(request.teamAPlayer1.savedPlayerID, "Precondition: this slot has no id yet")

        let resolvedID = try repository.upsertSavedPlayer(name: request.teamAPlayer1.name)?.id
        XCTAssertEqual(resolvedID, delon.id, "Should reuse the existing 'Delon' SavedPlayer, not create a duplicate")
    }
}
