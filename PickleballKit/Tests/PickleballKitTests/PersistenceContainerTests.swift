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
        XCTAssertEqual(historyEntityNames, ["TeamSide", "MatchRecord", "GameRecord", "PointEvent", "SavedPlayer"])
    }

    func testLocalOnlyContainerHoldsEveryModelInOneStoreWithoutCloudKit() throws {
        let container = try PersistenceContainer.makeLocalOnlyContainer(isStoredInMemoryOnly: true)
        XCTAssertEqual(container.configurations.count, 1)
        let configuration = try XCTUnwrap(container.configurations.first)
        // `CloudKitDatabase` is not Equatable, so compare its description with
        // `.none`'s (a CloudKit database prints its container identifier).
        XCTAssertEqual(
            String(describing: configuration.cloudKitDatabase),
            String(describing: ModelConfiguration.CloudKitDatabase.none)
        )
        let entityNames = Set((configuration.schema?.entities ?? []).map { $0.name })
        XCTAssertEqual(
            entityNames,
            ["TeamSide", "MatchRecord", "GameRecord", "PointEvent", "SavedPlayer", "InProgressGameState"]
        )
    }

    func testLocalOnlyContainerStoresAFinishedMatchAndASnapshot() throws {
        let context = ModelContext(try PersistenceContainer.makeLocalOnlyContainer(isStoredInMemoryOnly: true))
        let repository = MatchRepository(modelContext: context)
        let match = PickleballMatch(configuration: GameConfiguration(playMode: .singles), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 0..<11 { match.recordPoint(for: .teamA) }
        try repository.saveInProgressSnapshot(for: match, startedAt: Date())
        try repository.saveCompletedMatch(match, teamAName: "Team A", teamBName: "Team B", startedAt: Date())
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
        XCTAssertNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil))
    }
}
