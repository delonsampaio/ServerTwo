import SwiftUI
import SwiftData
import PickleballKit

/// A delete the user has asked for and not yet confirmed. The text for the
/// confirmation is read from the match when the request is made, so nothing
/// touches the match again once it may have been deleted.
struct PendingMatchDeletion {
    let match: MatchRecord
    let message: String

    init(match: MatchRecord) {
        let sides = match.teamSides ?? []
        let teamA = sides.first { $0.team == .teamA }?.displayName ?? "Team A"
        let teamB = sides.first { $0.team == .teamB }?.displayName ?? "Team B"
        let date = match.completedAt.formatted(date: .long, time: .omitted)
        self.match = match
        self.message = "\(teamA) vs \(teamB), \(date). This removes the scores and point-by-point log. Players and their other matches are not affected."
    }
}

extension Notification.Name {
    /// Posted after a match is deleted. Home and a player's screen load their
    /// matches once per view lifetime, so (like `matchPlayersEdited`) this makes
    /// them reload on their next appearance; see `refreshAfterPlayersEdited`.
    static let matchDeleted = Notification.Name("ServerTwo.matchDeleted")
}

/// A centered `.alert` (the app avoids `confirmationDialog` on iOS 27, where it
/// is a floating card near the top) that asks before a match is deleted, then
/// deletes it through the repository on the screen's own context.
private struct DeleteMatchAlert: ViewModifier {
    @Binding var pending: PendingMatchDeletion?
    /// Runs after the match was deleted and the notification was posted.
    let onDeleted: @MainActor () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var showFailure = false

    func body(content: Content) -> some View {
        content
            .alert(
                "Delete this match?",
                isPresented: Binding(
                    get: { pending != nil },
                    set: { isPresented in if !isPresented { pending = nil } }
                ),
                presenting: pending
            ) { request in
                Button("Delete", role: .destructive) { delete(request) }
                    .accessibilityIdentifier("ConfirmDeleteMatch")
                Button("Cancel", role: .cancel) { }
            } message: { request in
                Text(request.message)
            }
            .alert("Couldn't Delete Match", isPresented: $showFailure) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The match was not changed. Please try again.")
            }
    }

    private func delete(_ request: PendingMatchDeletion) {
        do {
            try MatchRepository(modelContext: modelContext).deleteMatch(request.match)
        } catch {
            showFailure = true
            return
        }
        NotificationCenter.default.post(name: .matchDeleted, object: nil)
        onDeleted()
    }
}

extension View {
    func deleteMatchAlert(
        pending: Binding<PendingMatchDeletion?>,
        onDeleted: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(DeleteMatchAlert(pending: pending, onDeleted: onDeleted))
    }
}
