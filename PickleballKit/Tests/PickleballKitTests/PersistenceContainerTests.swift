import XCTest
import SwiftData
@testable import PickleballKit

final class PersistenceContainerTests: XCTestCase {
    func testInMemoryContainerSupportsBothSchemas() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let context = ModelContext(container)

        let record = InProgressGameState(updatedAt: Date(), snapshotData: Data())
        context.insert(record)

        let match = MatchRecord(startedAt: Date(), completedAt: Date(), matchFormat: .bestOfOne, winningTeam: .teamA, configurationData: Data())
        context.insert(match)

        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<InProgressGameState>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MatchRecord>()).count, 1)
    }

    func testInProgressGameStateIsExcludedFromTheHistoryConfiguration() throws {
        // The spec's one hard sync rule: InProgressGameState must never be
        // CloudKit-synced. Verified at the container level, not just by
        // reading the source — a model added to the wrong list would
        // otherwise only be discovered at an actual CloudKit sync.
        let container = try PersistenceContainer.makeInMemoryContainer()

        let historyConfig = try XCTUnwrap(container.configurations.first { $0.name.hasPrefix("History-") })
        let inProgressConfig = try XCTUnwrap(container.configurations.first { $0.name.hasPrefix("InProgress-") })

        let historyEntityNames = Set((historyConfig.schema?.entities ?? []).map { $0.name })
        let inProgressEntityNames = Set((inProgressConfig.schema?.entities ?? []).map { $0.name })

        XCTAssertFalse(historyEntityNames.contains("InProgressGameState"))
        XCTAssertTrue(inProgressEntityNames.contains("InProgressGameState"))
        XCTAssertEqual(historyEntityNames, ["TeamSide", "MatchRecord", "GameRecord", "PointEvent"])
    }
}
