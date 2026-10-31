import SwiftUI
import SwiftData
import PickleballKit

@main
struct ServerTwoWatchApp: App {
    @State private var session: StandaloneMatchSession
    private let modelContainer: ModelContainer
    private let initialStage: WatchRootView.Stage

    init() {
        var stage = WatchRootView.Stage.home
        let container = Self.makeContainer()
        let repository = MatchRepository(modelContext: ModelContext(container))
        var pendingSync = PendingSyncStore()

        #if DEBUG
        // Screenshot/demo launches must not touch the real store or the real
        // pending-sync queue, so they get an in-memory store and a throwaway
        // defaults suite.
        let demo = WatchDemo(arguments: ProcessInfo.processInfo.arguments)
        if demo != nil {
            pendingSync = PendingSyncStore(userDefaults: UserDefaults(suiteName: "WatchDemo") ?? .standard)
        }
        #endif

        let session: StandaloneMatchSession
        #if DEBUG
        if demo != nil, let memory = try? PersistenceContainer.makeInMemoryContainer() {
            session = StandaloneMatchSession(
                repository: MatchRepository(modelContext: ModelContext(memory)), pendingSync: pendingSync
            )
            stage = demo?.apply(to: session) ?? .home
        } else {
            session = StandaloneMatchSession(repository: repository, pendingSync: pendingSync)
            session.resumeIfNeeded()
        }
        #else
        session = StandaloneMatchSession(repository: repository, pendingSync: pendingSync)
        // A match interrupted by a crash or a relaunch comes straight back.
        session.resumeIfNeeded()
        #endif

        self.modelContainer = container
        self.initialStage = stage
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(session: session, initialStage: initialStage)
        }
        .modelContainer(modelContainer)
    }

    /// The Watch store is local-only (no iCloud entitlement). If the on-disk
    /// store cannot be opened, scoring still has to work, so fall back to an
    /// in-memory store rather than failing at launch; the match in progress
    /// then simply isn't recoverable after a relaunch.
    private static func makeContainer() -> ModelContainer {
        if let container = try? PersistenceContainer.makeLocalOnlyContainer() { return container }
        do {
            return try PersistenceContainer.makeLocalOnlyContainer(isStoredInMemoryOnly: true)
        } catch {
            fatalError("Failed to create any model container: \(error)")
        }
    }
}
