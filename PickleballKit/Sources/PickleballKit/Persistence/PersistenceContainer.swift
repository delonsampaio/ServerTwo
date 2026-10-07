import SwiftData
import Foundation

public enum PersistenceContainer {
    public static let cloudKitContainerIdentifier = "iCloud.com.delonsampaio.ServerTwo"

    private static var historySchema: Schema {
        Schema([TeamSide.self, MatchRecord.self, GameRecord.self, PointEvent.self])
    }

    private static var inProgressSchema: Schema {
        Schema([InProgressGameState.self])
    }

    private static var fullSchema: Schema {
        Schema([TeamSide.self, MatchRecord.self, GameRecord.self, PointEvent.self, InProgressGameState.self])
    }

    /// The real container used by the app: completed-match history syncs via
    /// CloudKit, the in-progress snapshot stays local-only.
    public static func makeContainer() throws -> ModelContainer {
        let historyConfiguration = ModelConfiguration(
            "History",
            schema: historySchema,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        let inProgressConfiguration = ModelConfiguration(
            "InProgress",
            schema: inProgressSchema,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: historyConfiguration, inProgressConfiguration)
    }

    /// An in-memory container with no CloudKit involvement, for tests. Each
    /// call gets uniquely-named configurations — reusing a fixed name like
    /// "History" across many in-memory containers in the same test process
    /// causes SwiftData to bleed state between what should be isolated
    /// containers.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let suffix = UUID().uuidString
        let historyConfiguration = ModelConfiguration(
            "History-\(suffix)",
            schema: historySchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let inProgressConfiguration = ModelConfiguration(
            "InProgress-\(suffix)",
            schema: inProgressSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: historyConfiguration, inProgressConfiguration)
    }
}
