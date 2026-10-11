import Foundation

/// A one-shot payload from Home's "Quick Start" frequent-partners row: fill
/// Setup's name fields in order (Team A Player 1, Team A Player 2, Team B
/// Player 1, Team B Player 2) with up to 4 players selected on Home before
/// ever navigating to Setup — one trip, not one navigation per player.
/// Plain value type for the same reason `RematchRequest` is: no
/// `SavedPlayer` object crosses a tab/view boundary, only its id.
struct QuickStartRequest: Equatable, Identifiable {
    struct PlayerSlot: Equatable {
        let name: String
        let savedPlayerID: UUID
    }

    let id = UUID()
    /// 1 to 4 players, in the order they fill Setup's slots.
    let players: [PlayerSlot]

    static func == (lhs: QuickStartRequest, rhs: QuickStartRequest) -> Bool {
        lhs.id == rhs.id
    }
}
