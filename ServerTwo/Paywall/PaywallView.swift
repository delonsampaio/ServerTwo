import SwiftUI
import SwiftData
import PickleballKit

struct PaywallView: View {
    @Environment(ActiveMatchController.self) private var activeMatchController
    @Environment(\.dismiss) private var dismiss
    // 48 pt at the default text size; scales with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var lockIconSize: CGFloat = 48

    var body: some View {
        NavigationStack {
            AdaptiveScroll {
                VStack(spacing: 20) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockIconSize))
                        .foregroundStyle(.tint)
                    Text("You've Reached the Free Demo Limit")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("The free version lets you play \(activeMatchController.demoMatchLimit) full match\(activeMatchController.demoMatchLimit == 1 ? "" : "es"), start to finish. Unlock Server Two Pro for a one-time $1.99 to play unlimited matches, forever.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    Button {
                        activeMatchController.unlockPro()
                        dismiss()
                    } label: {
                        Text("Unlock Pro — $1.99")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("Unlock Pro — $1.99")

                    Button("Restore Purchases") {
                        // Stub: Phase 4 wires this to a real StoreKit restore call.
                    }
                    .foregroundStyle(.secondary)
                    .disabled(true)
                }
            }
            .padding()
            .navigationTitle("Server Two Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                        .accessibilityIdentifier("Not Now")
                }
            }
        }
    }
}

#Preview {
    PaywallView()
        .environment(try! ActiveMatchController(modelContext: ModelContext(PersistenceContainer.makeInMemoryContainer())))
}
