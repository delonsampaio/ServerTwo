import SwiftUI
import SwiftData
import PickleballKit

@main
struct MyApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private let modelContainer: ModelContainer
    private let liveActivity: LiveActivityController
    #if canImport(WatchConnectivity)
    /// Strongly held for the app's lifetime: it is the WCSession delegate.
    private let watchSync: PhoneWatchSync
    #endif
    @State private var activeMatchController: ActiveMatchController
    @State private var appSettings: AppSettings
    @State private var voiceAnnouncer: VoiceAnnouncer
    @State private var storeManager: StoreManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container: ModelContainer
        do {
            container = try PersistenceContainer.makeContainer()
        } catch {
            fatalError("Failed to create persistent container: \(error)")
        }
        self.modelContainer = container
        let settings = AppSettings()
        let liveActivity = LiveActivityController(
            host: MyApp.makeLiveActivityHost(),
            isEnabled: { settings.liveActivityEnabled }
        )
        self.liveActivity = liveActivity
        let controller = ActiveMatchController(modelContext: ModelContext(container), liveActivity: liveActivity)
        _activeMatchController = State(initialValue: controller)
        #if canImport(WatchConnectivity)
        // Created and activated here, before any view exists, so a match the
        // Watch delivered while the app was closed is not dropped. Imports go
        // through the main context (the one SwiftUI reads), and a successful
        // import feeds the demo counter like a match played here.
        let receiver = WatchMatchReceiver(
            repository: MatchRepository(modelContext: container.mainContext),
            didImport: { controller.recordCompletedMatchSaved(historyCountBeforeSave: $0) }
        )
        // The Watch's free-demo gate needs the Pro flag and the shared match
        // count: pushed at activation, on an entitlement change and whenever a
        // match is counted (`onDemoStateChanged`).
        let watchSync = PhoneWatchSync(
            handler: { incoming, acknowledger in
                guard receiver.receive(incoming, acknowledger: acknowledger) == .imported else { return }
                NotificationCenter.default.post(name: .matchSyncedFromWatch, object: nil)
            },
            onActivated: { [controller] in controller.onDemoStateChanged?() }
        )
        let publisher = PhoneStatePublisher(
            pusher: watchSync,
            isPro: { [controller] in controller.proUnlocked },
            completedMatchCount: { [controller] in controller.completedMatchCount }
        )
        controller.onDemoStateChanged = { publisher.publish() }
        watchSync.activate()
        self.watchSync = watchSync
        #endif
        // StoreManager is the source of truth for Pro; the controller (which
        // has no StoreKit import) just receives each refreshed result.
        _storeManager = State(initialValue: StoreManager(
            backend: MyApp.makeStoreBackend(),
            onEntitlementChange: { controller.proUnlocked = $0 }
        ))
        _appSettings = State(initialValue: settings)
        _voiceAnnouncer = State(initialValue: VoiceAnnouncer(
            output: MyApp.makeSpeechOutput(),
            isEnabled: { settings.voiceAnnouncerEnabled }
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(initialTab: activeMatchController.match != nil ? .play : .home)
                .environment(activeMatchController)
                .environment(appSettings)
                .environment(voiceAnnouncer)
                .environment(storeManager)
                .onChange(of: appSettings.voiceAnnouncerEnabled) { _, enabled in
                    if !enabled { voiceAnnouncer.stop() }
                }
                .onChange(of: appSettings.liveActivityEnabled) {
                    liveActivity.enablementChanged()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { voiceAnnouncer.stop() }
                    if phase == .active { liveActivity.retryIfNeeded() }
                }
                .modelContainer(modelContainer)
                .preferredColorScheme(appSettings.theme.colorScheme)
                .sheet(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { isPresented in
                        if !isPresented { hasSeenOnboarding = true }
                    }
                )) {
                    OnboardingView(modelContext: modelContainer.mainContext)
                }
                .task {
                    applyTestOverridesIfNeeded()
                    startDemoLiveActivityIfRequested()
                    await storeManager.start()
                }
        }
    }

    /// UI tests must never touch the audio session: any `-UITest-` launch
    /// argument (Debug builds only) swaps real speech for a no-op output.
    static func makeSpeechOutput(arguments: [String] = ProcessInfo.processInfo.arguments) -> SpeechOutput {
        #if DEBUG
        if arguments.contains(where: { $0.hasPrefix("-UITest-") }) {
            return NullSpeechOutput()
        }
        #endif
        return SystemSpeechOutput.live()
    }

    /// UI tests must never touch ActivityKit: any `-UITest-` launch argument
    /// (Debug builds only) swaps the real Live Activity host for a no-op.
    static func makeLiveActivityHost(arguments: [String] = ProcessInfo.processInfo.arguments) -> any LiveActivityHosting {
        #if DEBUG
        if arguments.contains(where: { $0.hasPrefix("-UITest-") }) {
            return NoOpLiveActivityHost()
        }
        #endif
        #if canImport(ActivityKit)
        return ActivityKitLiveActivityHost()
        #else
        // visionOS (also listed in this target's platforms) has no ActivityKit.
        return NoOpLiveActivityHost()
        #endif
    }

    /// Debug-only: `-Debug-DemoLiveActivity` shows a sample Live Activity
    /// without playing a match, to check the Lock Screen / Dynamic Island
    /// layouts. Compiled out of Release builds.
    private func startDemoLiveActivityIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-Debug-DemoLiveActivity") else { return }
        liveActivity.begin(attributes: .debugDemo, state: .debugDemoMidGame)
        #endif
    }

    /// UI tests must never reach the App Store: any `-UITest-` launch argument
    /// (Debug builds only) swaps StoreKit for a fake with an instant price
    /// whose purchase unlocks Pro. Real StoreKit paths are covered by
    /// `SKTestSession` unit tests.
    static func makeStoreBackend(arguments: [String] = ProcessInfo.processInfo.arguments) -> any StoreBackend {
        #if DEBUG
        if arguments.contains(where: { $0.hasPrefix("-UITest-") }) {
            let scenario = arguments.firstIndex(of: "-UITest-StoreScenario")
                .flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
                .flatMap(FakeStoreBackend.Scenario.init(rawValue:))
            return FakeStoreBackend(scenario: scenario ?? .normal)
        }
        #endif
        return StoreKitBackend()
    }

    /// Test-only seam: lets XCUITests force a clean slate, a locked
    /// entitlement, and a low demo match limit, so a test doesn't depend on
    /// whatever a previous run left in `UserDefaults`/the store — including
    /// completed match history, which (unlike a mid-game point cap) now
    /// directly determines whether `canStartNewMatch` is true, and every
    /// saved player (including whichever one is "Me" — without this, a
    /// `isMe` flag set by an earlier run could silently survive and make a
    /// later run's own "mark as Me" step a no-op). Only takes effect when
    /// these specific launch arguments are present — never active in a
    /// normal launch, including TestFlight/App Store builds, since no real
    /// launch path passes them.
    ///
    /// The body is additionally wrapped in `#if DEBUG` so this monetization/
    /// state bypass compiles out of Release builds entirely rather than
    /// merely being unreachable in them. XCUITests run against a Debug
    /// build, so `GoldenPathUITests`/`PaywallTriggerUITests` are unaffected.
    private func applyTestOverridesIfNeeded() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITest-ResetState") else { return }
        activeMatchController.proUnlocked = false
        activeMatchController.clearAnyInProgressMatchForTesting()
        activeMatchController.clearAllMatchHistoryForTesting()
        // Without this, `hasSeenOnboarding` (backed by UserDefaults.standard,
        // not touched by anything above) stays true for the lifetime of the
        // simulator once onboarding has been dismissed once — meaning no
        // test after the very first run of the day could ever exercise
        // OnboardingView again, "-UITest-ResetState" or not. This runs after
        // `.sheet`'s binding was first evaluated, but `@AppStorage` is
        // observable, so flipping it here still reactively presents the
        // sheet a moment later on this same launch — it doesn't require
        // waiting for the next one.
        hasSeenOnboarding = false
        if let limitIndex = arguments.firstIndex(of: "-UITest-DemoMatchLimit"),
           limitIndex + 1 < arguments.count,
           let limit = Int(arguments[limitIndex + 1]) {
            activeMatchController.demoMatchLimit = limit
        }
        #endif
    }
}
