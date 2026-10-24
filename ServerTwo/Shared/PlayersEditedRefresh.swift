import SwiftUI

extension Notification.Name {
    /// Posted after Edit Players saves. History, Home and a player's screen
    /// each load their matches once per view lifetime, so a plain pop back
    /// would otherwise leave their rows and stats stale until pull-to-refresh.
    static let matchPlayersEdited = Notification.Name("ServerTwo.matchPlayersEdited")
}

/// Reloads a screen's matches once, the next time it appears after an edit.
/// The notification only marks the screen stale; the reload waits for the
/// next `onAppear` so it never runs while a pushed Match Detail (or the
/// sheet) that belongs to this screen is still on screen.
///
/// It reloads and bumps `revision`, nothing else. SwiftData's change tracking
/// did not reliably re-render rows after Edit Players changed a side (verified
/// in a UI test: the models were updated, the rows kept the old names), so the
/// screen applies `.id(revision)` to its ROW content only. Never put it on the
/// List/ScrollView root: that would reset the scroll position and re-run the
/// screen's `.task`.
private struct RefreshAfterPlayersEdited: ViewModifier {
    @Binding var revision: Int
    let reload: @MainActor () -> Void
    @State private var isStale = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .matchPlayersEdited)) { _ in
                isStale = true
            }
            .onAppear {
                guard isStale else { return }
                isStale = false
                reload()
                revision += 1
            }
    }
}

extension View {
    func refreshAfterPlayersEdited(revision: Binding<Int>, reload: @escaping @MainActor () -> Void) -> some View {
        modifier(RefreshAfterPlayersEdited(revision: revision, reload: reload))
    }
}
