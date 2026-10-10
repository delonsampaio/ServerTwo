// PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift
import XCTest
import SwiftData
@testable import PickleballKit

final class SavedPlayerRepositoryTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    func testUpsertSavedPlayerCreatesNewPlayerOnFirstUse() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let player = try repository.upsertSavedPlayer(name: "Delon")
        XCTAssertEqual(player?.name, "Delon")
        XCTAssertFalse(player?.isMe ?? true)

        let all = try repository.fetchAllSavedPlayers()
        XCTAssertEqual(all.count, 1)
    }

    func testUpsertSavedPlayerReusesExistingPlayerByExactTrimmedName() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let first = try repository.upsertSavedPlayer(name: "Delon")
        let second = try repository.upsertSavedPlayer(name: "  Delon  ")

        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(try repository.fetchAllSavedPlayers().count, 1)
    }

    func testUpsertSavedPlayerReturnsNilForBlankOrWhitespaceName() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        XCTAssertNil(try repository.upsertSavedPlayer(name: ""))
        XCTAssertNil(try repository.upsertSavedPlayer(name: "   "))
        XCTAssertEqual(try repository.fetchAllSavedPlayers().count, 0)
    }

    func testSetMePlayerClearsPreviousMeAndSetsNewOne() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let alice = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Alice"))
        let bob = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Bob"))
        try repository.setMePlayer(alice)
        XCTAssertEqual(try repository.fetchMePlayer()?.id, alice.id)

        try repository.setMePlayer(bob)
        let all = try repository.fetchAllSavedPlayers()
        XCTAssertEqual(all.filter(\.isMe).count, 1)
        XCTAssertEqual(try repository.fetchMePlayer()?.id, bob.id)
    }

    func testDeleteSavedPlayerNullifiesButDoesNotDeleteHistoricalMatch() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let delon = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        _ = try repository.saveCompletedMatch(
            match, teamAName: "Delon & Mike", teamBName: "Opponents", startedAt: Date(),
            teamAPlayers: [delon]
        )

        try repository.deleteSavedPlayer(delon)

        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 1)
        let teamA = history[0].teamSides?.first { $0.team == .teamA }
        XCTAssertEqual(teamA?.displayName, "Delon & Mike")
        XCTAssertEqual(teamA?.players?.count ?? 0, 0)
    }

    func testRenameSavedPlayerUpdatesNameAndIgnoresBlankInput() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let mike = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Mike"))
        let mikeID = mike.id

        try repository.renameSavedPlayer(mike, to: "Mike S.")
        XCTAssertEqual(mike.name, "Mike S.")
        XCTAssertEqual(mike.id, mikeID, "Rename must not change identity")

        try repository.renameSavedPlayer(mike, to: "   ")
        XCTAssertEqual(mike.name, "Mike S.", "A blank rename must be a no-op, not clear the name")
    }

    func testSaveCompletedMatchWithNoPlayersLeavesTeamSidePlayersEmpty() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        let saved = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())

        let teamA = saved.teamSides?.first { $0.team == .teamA }
        XCTAssertEqual(teamA?.players?.count ?? 0, 0)
    }

    func testSuggestedPlayersFiltersAndRanksByRecencyThenFrequency() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let alice = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Alice"))
        let abby = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Abby"))
        _ = try repository.upsertSavedPlayer(name: "Bob") // never played, should sort last and be excluded by the "Al" query

        func playMatch(players: [SavedPlayer], at date: Date) throws {
            let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
            for _ in 1...11 { match.recordPoint(for: .teamA) }
            _ = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: date, completedAt: date, teamAPlayers: players)
        }

        // Abby: 2 matches, most recent is older than Alice's most recent.
        try playMatch(players: [abby], at: Date(timeIntervalSince1970: 1000))
        try playMatch(players: [abby], at: Date(timeIntervalSince1970: 2000))
        // Alice: 1 match, but more recent than either of Abby's.
        try playMatch(players: [alice], at: Date(timeIntervalSince1970: 3000))

        let results = try repository.suggestedPlayers(matching: "Al")
        XCTAssertEqual(results.map(\.name), ["Alice"]) // "Bob" and "Abby" don't contain "Al"

        let allMatchingA = try repository.suggestedPlayers(matching: "A")
        XCTAssertEqual(allMatchingA.map(\.name), ["Alice", "Abby"]) // Alice ranks first: more recent match
    }
}
