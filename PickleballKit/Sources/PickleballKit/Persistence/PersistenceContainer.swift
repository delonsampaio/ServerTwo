import SwiftData
import Foundation

public enum PersistenceContainer {
    public static let cloudKitContainerIdentifier = "iCloud.com.delonsampaio.ServerTwo"

    // Single source of truth for each schema's model types — fullSchema is
    // derived from these two lists rather than hand-maintaining a third,
    // separately-written list that could silently drift out of sync (e.g.
    // a model added to one list and not the other either escapes CloudKit
    // exclusion or becomes unroutable). SwiftData's `Schema` type has no
    // API to merge two already-built `Schema` instances (`Schema.entities`
    // is `[Schema.Entity]`, which no public initializer accepts back in),
    // so the de-duplication happens at the model-type-array level instead.
    private static let historyModelTypes: [any PersistentModel.Type] = [
        TeamSide.self, MatchRecord.self, GameRecord.self, PointEvent.self
    ]

    private static let inProgressModelTypes: [any PersistentModel.Type] = [
        InProgressGameState.self
    ]

    private static var historySchema: Schema {
        Schema(historyModelTypes)
    }

    private static var inProgressSchema: Schema {
        Schema(inProgressModelTypes)
    }

    private static var fullSchema: Schema {
        Schema(historyModelTypes + inProgressModelTypes)
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
