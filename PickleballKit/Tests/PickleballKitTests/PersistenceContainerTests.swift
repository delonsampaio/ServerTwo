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
}
