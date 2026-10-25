import XCTest
import Combine
import SwiftData
@testable import ServerTwo
import PickleballKit

/// The pure part of "drop the deleted match from open screens at once": the id
/// removal, and the id surviving the notification. The screens' wiring is
/// covered by DeleteMatchUITests.
@MainActor
final class MatchDeletedDropTests: XCTestCase {
    private func saveMatch(_ repository: MatchRepository, scores: [(teamA: Int, teamB: Int)] = [(11, 7)]) throws -> MatchRecord {
        try repository.saveQuickLoggedMatch(
            configuration: GameConfiguration(winningScore: .eleven, winByTwo: true),
            matchFormat: .bestOfOne,
            teamAName: "A",
            teamBName: "B",
            gameScores: scores
        )
    }

    func testRemovingAnIDKeepsTheOtherMatchesInOrder() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let repository = MatchRepository(modelContext: ModelContext(container))
        let first = try saveMatch(repository)
        let second = try saveMatch(repository)
        let third = try saveMatch(repository)

        let remaining = [first, second, third].removing(modelID: second.persistentModelID)

        XCTAssertEqual(remaining.map(\.persistentModelID), [first.persistentModelID, third.persistentModelID])
    }

    func testRemovingAnIDThatIsNotPresentChangesNothing() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let repository = MatchRepository(modelContext: ModelContext(container))
        let only = try saveMatch(repository)
        let other = try saveMatch(repository)

        XCTAssertEqual([only].removing(modelID: other.persistentModelID).count, 1)
        XCTAssertTrue([MatchRecord]().removing(modelID: other.persistentModelID).isEmpty)
    }

    func testTheIDReadBeforeADeleteStillDropsTheDeletedRecordFromAHeldArray() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let repository = MatchRepository(modelContext: ModelContext(container))
        let keep = try saveMatch(repository)
        let doomed = try saveMatch(repository)
        let held = [keep, doomed]

        let id = doomed.persistentModelID
        try repository.deleteMatch(doomed)

        // Only ids are compared; no property of the deleted record is read.
        XCTAssertEqual(held.removing(modelID: id).map(\.persistentModelID), [keep.persistentModelID])
    }

    func testTheNotificationCarriesTheMatchIDAndRecordsItAsDeleted() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let match = try saveMatch(MatchRepository(modelContext: ModelContext(container)))

        var received: PersistentIdentifier?
        // A Combine sink (not a block observer) so the closure may touch this
        // main-actor test's local state under Swift 6.
        let subscription = NotificationCenter.default.publisher(for: .matchDeleted).sink { notification in
            received = MatchDeleted.matchID(in: notification)
        }
        defer { subscription.cancel() }

        MatchDeleted.post(matchID: match.persistentModelID)

        XCTAssertEqual(received, match.persistentModelID)
        XCTAssertTrue(MatchDeleted.hasBeenDeleted(match.persistentModelID), "rows check this by id before reading a possibly deleted match")
    }
}
