import SwiftData
import Foundation

/// A local-only, crash-recovery snapshot of the currently-live match.
/// Deliberately excluded from the CloudKit schema (see `PersistenceContainer`)
/// — it exists purely to resume this device's in-flight game after a crash
/// or relaunch, never to sync or be browsed.
@Model
public final class InProgressGameState {
    public var id: UUID = UUID()
    public var updatedAt: Date = Date()
    public var snapshotData: Data = Data()

    public init(id: UUID = UUID(), updatedAt: Date, snapshotData: Data) {
        self.id = id
        self.updatedAt = updatedAt
        self.snapshotData = snapshotData
    }
}
