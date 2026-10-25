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
        self.message = "\(teamA) vs \(teamB), \(date). This permanently deletes the scores and point-by-point log, removes the match from every player's record, and also deletes it on your other devices. This cannot be undone."
    }
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
        // Read before the delete: the id is the only thing that is safe to
        // read from the record afterwards.
        let deletedID = request.match.persistentModelID
        do {
            try MatchRepository(modelContext: modelContext).deleteMatch(request.match)
        } catch {
            showFailure = true
            return
        }
        MatchDeleted.post(matchID: deletedID)
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
