import SwiftUI
import SwiftData
import PickleballKit

@main
struct ServerTwoWatchApp: App {
    @State private var session: StandaloneMatchSession
    /// Held for the app's lifetime: the repository's context belongs to it.
    /// Nothing in the views uses SwiftData directly, so there is no
    /// `.modelContainer` modifier.
    private let modelContainer: ModelContainer
    private let initialFlow: WatchFlow

    init() {
        var flow = WatchFlow()
        let container = Self.makeContainer()
        let repository = MatchRepository(modelContext: ModelContext(container))
        var pendingSync = PendingSyncStore()

        #if DEBUG
        // Screenshot/demo launches must not touch the real store or the real
        // pending-sync queue, so they get an in-memory store and a throwaway
        // defaults suite.
        let demo = WatchDemo(arguments: ProcessInfo.processInfo.arguments)
        if demo != nil {
            pendingSync = PendingSyncStore(suiteName: "WatchDemo")
        }
        #endif

        let session: StandaloneMatchSession
        #if DEBUG
        if demo != nil, let memory = try? PersistenceContainer.makeInMemoryContainer() {
            session = StandaloneMatchSession(
                repository: MatchRepository(modelContext: ModelContext(memory)), pendingSync: pendingSync
            )
            flow = demo?.apply(to: session) ?? WatchFlow()
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
        self.initialFlow = flow
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(session: session, initialFlow: initialFlow)
        }
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
