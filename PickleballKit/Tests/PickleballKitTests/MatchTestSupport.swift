import XCTest
@testable import PickleballKit

/// Plays out one whole game for `winner` without assuming who serves first:
/// in side-out scoring only the serving team scores, so a winner who is
/// receiving first has to win the side-outs. Taps the winner's `recordPoint`
/// until the match archives one more game (bounded, so a bug fails instead of
/// hanging).
func playOutGame(
    _ match: PickleballMatch,
    winner: Team,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let target = match.completedGames.count + 1
    var taps = 0
    while match.completedGames.count < target, taps < 200 {
        match.recordPoint(for: winner)
        taps += 1
    }
    XCTAssertEqual(match.completedGames.count, target, "the game never finished for \(winner)", file: file, line: line)
}
