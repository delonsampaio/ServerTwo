import Foundation

/// A one-shot payload from Home's "Quick Start" frequent-partners row:
/// pre-fill Team A's first player, nothing else. Deliberately lighter than
/// `RematchRequest` — this isn't "repeat a whole match," just "I know who's
/// on my side, let me skip typing their name." Plain value type for the
/// same reason `RematchRequest` is: no `SavedPlayer` object crosses a
/// tab/view boundary, only its id.
struct QuickStartRequest: Equatable, Identifiable {
    let id = UUID()
    let playerName: String
    let savedPlayerID: UUID

    static func == (lhs: QuickStartRequest, rhs: QuickStartRequest) -> Bool {
        lhs.id == rhs.id
    }
}
