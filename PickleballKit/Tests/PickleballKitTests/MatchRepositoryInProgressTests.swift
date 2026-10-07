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

        try repository.saveInProgressSnapshot(for: match)

        let loaded = try repository.loadInProgressMatch()
        let resumedMatch = try XCTUnwrap(loaded)
        XCTAssertEqual(resumedMatch.currentGame.state.teamAScore, 2)
        XCTAssertTrue(resumedMatch.currentGame.canUndo)
    }

    func testSavingASecondSnapshotReplacesTheFirstRatherThanAccumulating() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let firstMatch = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        firstMatch.recordPoint(for: .teamA)
        try repository.saveInProgressSnapshot(for: firstMatch)

        let secondMatch = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamB, proUnlocked: true, demoPointCap: nil)
        secondMatch.recordPoint(for: .teamB)
        secondMatch.recordPoint(for: .teamB)
        try repository.saveInProgressSnapshot(for: secondMatch)

        let allRecords = try context.fetch(FetchDescriptor<InProgressGameState>())
        XCTAssertEqual(allRecords.count, 1)

        let loaded = try repository.loadInProgressMatch()
        let resumedMatch = try XCTUnwrap(loaded)
        XCTAssertEqual(resumedMatch.currentGame.state.teamBScore, 2)
    }

    func testLoadWithNoSavedSnapshotReturnsNil() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let loaded = try repository.loadInProgressMatch()
        XCTAssertNil(loaded)
    }

    func testClearInProgressSnapshotRemovesIt() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        try repository.saveInProgressSnapshot(for: match)
        try repository.clearInProgressSnapshot()
        let loaded = try repository.loadInProgressMatch()
        XCTAssertNil(loaded)
    }
}
