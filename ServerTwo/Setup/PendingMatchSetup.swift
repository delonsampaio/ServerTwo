import Foundation
import PickleballKit

/// Everything Setup decides except who serves first — captured the instant
/// "Start Match" is tapped, but `PickleballMatch` isn't created yet, since
/// its initializer requires `firstServingTeam`. `ActiveMatchController`
/// holds this while the new coin-flip screen is up, then turns it into a
/// real match via `confirmFirstServe`.
///
/// Player ids, never `SavedPlayer` objects — same cross-`ModelContext`
/// reasoning as `ActiveMatchController`'s existing `teamAPlayerIDs`/
/// `teamBPlayerIDs`: this controller's `ModelContext` isn't the one views
/// read from, so a live model object handed in here would risk the same
/// cross-context bug already found and fixed once in this project.
struct PendingMatchSetup: Equatable {
    let configuration: GameConfiguration
    let matchFormat: MatchFormat
    let teamAName: String
    let teamBName: String
    let teamAPlayerIDs: [UUID]
    let teamBPlayerIDs: [UUID]

    /// Falls back to "Team A"/"Team B" when no names were typed — shared by
    /// the coin-flip screen's button labels and `confirmFirstServe`, so a
    /// blank team name reads the same way in both places instead of two
    /// separately-maintained fallbacks drifting apart.
    var resolvedTeamAName: String {
        teamAName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team A" : teamAName
    }

    var resolvedTeamBName: String {
        teamBName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team B" : teamBName
    }
}
