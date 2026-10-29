// Compiled into BOTH the app and the Live Activity extension (this folder is a
// synchronized group of both targets), because ActivityKit needs the very same
// attributes type on both sides. It stays dependency free on purpose: the
// extension only ever READS a ContentState the system hands it, so it must not
// need PickleballKit (and through it SwiftData). The mapping from a live
// match lives in the app target (`PickleballActivityAttributes+Match.swift`).
import Foundation

// `nonisolated` because both targets default to MainActor isolation, and an
// isolated conformance to ActivityAttributes (Sendable) would not compile.
//
// The data type itself does not import ActivityKit: the app target also lists
// visionOS, where ActivityKit does not exist, and the app code only needs this
// plain value type there (it falls back to a no-op host). Only the
// ActivityAttributes conformance below is guarded.
nonisolated struct PickleballActivityAttributes: Codable, Hashable, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var teamAScore: Int
        var teamBScore: Int
        var teamAGamesWon: Int
        var teamBGamesWon: Int
        /// `Team.rawValue`, not `Team`: the extension has no PickleballKit.
        /// "teamA" / "teamB".
        var servingTeamRawValue: String
        /// 1 or 2 in doubles side-out scoring (the badge shows SERVER 1/2),
        /// nil for singles and rally scoring where the number means nothing.
        var serverNumber: Int?
        var isMatchOver: Bool

        var isTeamAServing: Bool { servingTeamRawValue == "teamA" }
    }

    let teamAName: String
    let teamBName: String
    /// Precomputed once, e.g. "Doubles • Best of 3".
    let matchFormatSummary: String
    /// Whether the match has more than one game, so the games-won tally is
    /// worth showing. Static: it never changes during a match.
    let showsGamesWon: Bool
}

#if canImport(ActivityKit)
import ActivityKit

extension PickleballActivityAttributes: ActivityAttributes {}
#endif
