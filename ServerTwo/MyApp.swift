import SwiftUI
import SwiftData
import PickleballKit

@main
struct MyApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private let modelContainer: ModelContainer
    @State private var activeMatchController: ActiveMatchController
    @State private var appSettings = AppSettings()

    init() {
        let container: ModelContainer
        do {
            container = try PersistenceContainer.makeContainer()
        } catch {
            fatalError("Failed to create persistent container: \(error)")
        }
        self.modelContainer = container
        _activeMatchController = State(initialValue: ActiveMatchController(modelContext: ModelContext(container)))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(activeMatchController)
                .environment(appSettings)
                .modelContainer(modelContainer)
                .preferredColorScheme(appSettings.theme.colorScheme)
                .sheet(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { isPresented in
                        if !isPresented { hasSeenOnboarding = true }
                    }
                )) {
                    OnboardingView()
                }
                .task {
                    applyTestOverridesIfNeeded()
                }
        }
    }

    /// Test-only seam: lets XCUITests force a clean slate, a locked
    /// entitlement, and a low demo match limit, so a test doesn't depend on
    /// whatever a previous run left in `UserDefaults`/the store — including
    /// completed match history, which (unlike a mid-game point cap) now
    /// directly determines whether `canStartNewMatch` is true. Only takes
    /// effect when these specific launch arguments are present — never
    /// active in a normal launch, including TestFlight/App Store builds,
    /// since no real launch path passes them.
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
        if let limitIndex = arguments.firstIndex(of: "-UITest-DemoMatchLimit"),
           limitIndex + 1 < arguments.count,
           let limit = Int(arguments[limitIndex + 1]) {
            activeMatchController.demoMatchLimit = limit
        }
        #endif
    }
}
