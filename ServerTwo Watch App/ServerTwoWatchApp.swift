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
    /// Held for the app's lifetime: it owns the WCSession delegate, which must
    /// exist from launch so a queued acknowledgement is not dropped.
    private let syncCoordinator: WatchSyncCoordinator
    private let access: WatchAccess

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
        // Standard defaults in the real app; a throwaway suite for demos.
        let counterSuite: String? = demo != nil ? "WatchDemo" : nil
        #endif

        let session: StandaloneMatchSession
        var syncRepository = repository
        #if DEBUG
        if demo != nil, let memory = try? PersistenceContainer.makeInMemoryContainer() {
            syncRepository = MatchRepository(modelContext: ModelContext(memory))
            session = StandaloneMatchSession(
                repository: syncRepository, pendingSync: pendingSync,
                lifetimeCounter: WatchLifetimeCounter(suiteName: counterSuite)
            )
            flow = demo?.apply(to: session) ?? WatchFlow()
        } else {
            session = StandaloneMatchSession(
                repository: repository, pendingSync: pendingSync,
                lifetimeCounter: WatchLifetimeCounter(suiteName: counterSuite)
            )
            session.resumeIfNeeded()
        }
        #else
        session = StandaloneMatchSession(
            repository: repository, pendingSync: pendingSync, lifetimeCounter: WatchLifetimeCounter()
        )
        // A match interrupted by a crash or a relaunch comes straight back.
        session.resumeIfNeeded()
        #endif

        // The sync repository is the one the session saves through, so a
        // delete after an acknowledgement happens in the context that holds the
        // record. Done and launch activation trigger the sync.
        let coordinator = WatchSyncCoordinator(
            repository: syncRepository, pendingSync: pendingSync, transport: WatchSessionTransport(), session: session
        )
        // The free-demo gate: StoreKit Pro here, or Pro and the shared match
        // count pushed by the iPhone (cached, so it works offline from Apple).
        let access: WatchAccess
        #if DEBUG
        if let demo {
            access = demo.makeAccess(suiteName: "WatchDemo")
        } else {
            access = WatchAccess(
                counter: WatchLifetimeCounter(), cache: WatchEntitlementCache(), entitlements: WatchStoreKitEntitlements()
            )
        }
        #else
        access = WatchAccess(
            counter: WatchLifetimeCounter(), cache: WatchEntitlementCache(), entitlements: WatchStoreKitEntitlements()
        )
        #endif
        coordinator.onPhoneState = { access.apply($0) }
        coordinator.start()
        #if DEBUG
        WatchAutoSync.playAndFinishIfRequested(on: session, arguments: ProcessInfo.processInfo.arguments)
        #endif

        self.modelContainer = container
        self.initialFlow = flow
        self.syncCoordinator = coordinator
        self.access = access
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(session: session, access: access, initialFlow: initialFlow)
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
