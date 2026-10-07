import XCTest
import SwiftData
@testable import PickleballKit

final class MatchRepositoryInProgressTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    func testSaveAndLoadInProgressSnapshotRoundTrips() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        match.recordPoint(for: .teamA)
        match.recordPoint(for: .teamA)

        let startedAt = Date(timeIntervalSince1970: 1000)
        try repository.saveInProgressSnapshot(for: match, startedAt: startedAt)

        let loaded = try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil)
        let resumed = try XCTUnwrap(loaded)
        XCTAssertEqual(resumed.startedAt, startedAt)
        XCTAssertEqual(resumed.match.currentGame.state.teamAScore, 2)
        XCTAssertTrue(resumed.match.currentGame.canUndo)
    }

    func testSavingASecondSnapshotReplacesTheFirstRatherThanAccumulating() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let firstMatch = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        firstMatch.recordPoint(for: .teamA)
        try repository.saveInProgressSnapshot(for: firstMatch, startedAt: Date())

        let secondMatch = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamB, proUnlocked: true, demoPointCap: nil)
        secondMatch.recordPoint(for: .teamB)
        secondMatch.recordPoint(for: .teamB)
        try repository.saveInProgressSnapshot(for: secondMatch, startedAt: Date())

        let allRecords = try context.fetch(FetchDescriptor<InProgressGameState>())
        XCTAssertEqual(allRecords.count, 1)

        let loaded = try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil)
        let resumed = try XCTUnwrap(loaded)
        XCTAssertEqual(resumed.match.currentGame.state.teamBScore, 2)
    }

    func testLoadWithNoSavedSnapshotReturnsNil() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let loaded = try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil)
        XCTAssertNil(loaded)
    }

    func testClearInProgressSnapshotRemovesIt() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        try repository.saveInProgressSnapshot(for: match, startedAt: Date())
        try repository.clearInProgressSnapshot()
        let loaded = try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil)
        XCTAssertNil(loaded)
    }

    func testLoadingAFinishedSnapshotSelfHealsByClearingItAndReturningNil() throws {
        // A snapshot can only ever reach "match over" if the app crashed or
        // was force-quit after the match-deciding point but before
        // saveCompletedMatch's own clear ran. There's nothing to resume.
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        try repository.saveInProgressSnapshot(for: match, startedAt: Date())

        let loaded = try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil)
        XCTAssertNil(loaded)

        let remaining = try context.fetch(FetchDescriptor<InProgressGameState>())
        XCTAssertTrue(remaining.isEmpty)
    }
}
