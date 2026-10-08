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
    /// entitlement, and a low demo cap, so a test doesn't depend on
    /// whatever a previous run left in `UserDefaults`/the store, and
    /// doesn't need 11 real taps to reach the cap. Only takes effect when
    /// these specific launch arguments are present — never active in a
    /// normal launch, including TestFlight/App Store builds, since no real
    /// launch path passes them.
    private func applyTestOverridesIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITest-ResetState") else { return }
        activeMatchController.proUnlocked = false
        activeMatchController.clearAnyInProgressMatchForTesting()
        if let capIndex = arguments.firstIndex(of: "-UITest-DemoPointCap"),
           capIndex + 1 < arguments.count,
           let cap = Int(arguments[capIndex + 1]) {
            activeMatchController.demoPointCap = cap
        }
    }
}
