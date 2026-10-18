import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

@MainActor
final class MatchDetailViewTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    /// Builds and saves a match with exactly the given per-game final
    /// scores (team A's score, team B's score), optionally supplying
    /// `gameCompletionDates` to simulate a freshly-played match (real
    /// timestamps) vs. pre-feature history (omitted entirely, so every
    /// `completedAt` stays nil — see Task 2).
    private func saveMatch(
        context: ModelContext,
        gameScores: [(Int, Int)],
        gameCompletionDates: [Date?] = []
    ) throws -> MatchRecord {
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)
        let matchFormat: MatchFormat = gameScores.count == 1 ? .bestOfOne : .bestOfThree
        let match = PickleballMatch(configuration: config, matchFormat: matchFormat, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for (teamAScore, teamBScore) in gameScores {
            // DEVIATION FROM BRIEF: the brief's own helper scored the
            // loser's points first, then the winner's, "so the winner's
            // final point is also the game-deciding one." That breaks
            // for a deuce finish like (15, 13): PickleballGame.recordPoint
            // ends the game the instant ANY team reaches winningScore
            // (11) while leading by 2+, checked after every single
            // point. Scoring the "loser" (13) uncontested first means
            // they hit 11-0 (lead 11, >= winningScore 11) and the game
            // ends right there — for the WRONG team, at the WRONG score
            // — long before the intended (15, 13) margin exists. The
            // match then silently starts a brand-new game for the
            // remaining taps, fragmenting one intended game into several
            // real ones.
            //
            // Fix: alternate points 1-for-1 up to the lower score first.
            // A tied score can never satisfy `gameWinner`'s `a != b`
            // check, no matter how high, so this never ends the game
            // prematurely. Only then award the winner's remaining
            // margin consecutively — still landing the winner's final
            // point as the game-deciding one, matching the brief's own
            // intent, just safe for deuce scores too.
            let tiedAt = min(teamAScore, teamBScore)
            for _ in 0..<tiedAt {
                match.recordPoint(for: .teamA)
                match.recordPoint(for: .teamB)
            }
            let winner: Team = teamAScore > teamBScore ? .teamA : .teamB
            for _ in 0..<abs(teamAScore - teamBScore) {
                match.recordPoint(for: winner)
            }
        }
        return try repository.saveCompletedMatch(
            match,
            teamAName: "A",
            teamBName: "B",
            startedAt: Date(timeIntervalSince1970: 0),
            gameCompletionDates: gameCompletionDates
        )
    }

    func testBestOfOneMatchHasNoClosestOrLongestGame() throws {
        let context = try makeContext()
        let record = try saveMatch(context: context, gameScores: [(11, 7)], gameCompletionDates: [Date()])
        let view = MatchDetailView(match: record, onRematch: { _ in })

        XCTAssertNil(view.closestGameID)
        XCTAssertNil(view.longestGameID)
    }

    func testEveryGameWithIdenticalMarginHasNoClosestGame() throws {
        let context = try makeContext()
        // Both games decided by exactly 11 points (11-0 twice) — nothing
        // distinguishes a "closest" one.
        let record = try saveMatch(context: context, gameScores: [(11, 0), (11, 0)], gameCompletionDates: [Date(), Date()])
        let view = MatchDetailView(match: record, onRematch: { _ in })

        XCTAssertNil(view.closestGameID)
    }

    func testMarginTieBreaksTowardHigherTotalScore() throws {
        let context = try makeContext()
        // Both games have a 2-point margin (11-9 and 15-13) — the deeper
        // game (15-13, higher combined total) should win the tiebreak.
        let record = try saveMatch(context: context, gameScores: [(11, 9), (15, 13)])
        let games = try XCTUnwrap(record.games).sorted { $0.gameNumber < $1.gameNumber }
        let view = MatchDetailView(match: record, onRematch: { _ in })

        XCTAssertEqual(view.closestGameID, games[1].id)
    }

    func testPreFeatureHistoryShowsClosestGameButNeverLongestGame() throws {
        let context = try makeContext()
        // No gameCompletionDates at all — simulates a match saved before
        // this feature shipped. closestGameID only needs final scores
        // (already present); longestGameID needs real timestamps, which
        // this match doesn't have, and must stay nil rather than guess.
        let record = try saveMatch(context: context, gameScores: [(11, 9), (11, 2)])
        let view = MatchDetailView(match: record, onRematch: { _ in })

        XCTAssertNotNil(view.closestGameID)
        XCTAssertNil(view.longestGameID)
    }

    func testLongestGameIsNilWhenAnySingleGameLacksACompletionDate() throws {
        let context = try makeContext()
        // Three games, but only two completion dates — simulates a
        // crash-resumed match whose first game predates this session's
        // own timestamp capture (see Task 3). Must skip the whole
        // longest-game computation rather than measure some games
        // against a stale checkpoint.
        let record = try saveMatch(
            context: context,
            gameScores: [(11, 7), (9, 11), (11, 5)],
            gameCompletionDates: [nil, Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 2000)]
        )
        let view = MatchDetailView(match: record, onRematch: { _ in })

        XCTAssertNil(view.longestGameID)
    }

    func testLongestGameIsTheOneWithTheGreatestDurationBetweenCheckpoints() throws {
        let context = try makeContext()
        // Game 1 takes 100s (0 -> 100), game 2 takes 500s (100 -> 600) -
        // game 2 is the longest despite being the lower-scoring game.
        let record = try saveMatch(
            context: context,
            gameScores: [(11, 7), (11, 9)],
            gameCompletionDates: [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 600)]
        )
        let games = try XCTUnwrap(record.games).sorted { $0.gameNumber < $1.gameNumber }
        let view = MatchDetailView(match: record, onRematch: { _ in })

        XCTAssertEqual(view.longestGameID, games[1].id)
    }

    func testDurationTextIsNilWhenStartedAtExactlyEqualsCompletedAt() {
        // Quick Log sets both timestamps to the same Date() — must read as
        // "we don't know," not "< 1 min" (which would look like a bug).
        let record = MatchRecord(
            startedAt: Date(timeIntervalSince1970: 1000),
            completedAt: Date(timeIntervalSince1970: 1000),
            matchFormat: .bestOfOne,
            winningTeam: .teamA,
            configurationData: Data()
        )
        let view = MatchDetailView(match: record, onRematch: { _ in })

        XCTAssertNil(view.durationText)
    }

    func testDurationTextStillShowsUnderAMinuteForAGenuinelyShortLiveMatch() {
        let record = MatchRecord(
            startedAt: Date(timeIntervalSince1970: 1000),
            completedAt: Date(timeIntervalSince1970: 1030),
            matchFormat: .bestOfOne,
            winningTeam: .teamA,
            configurationData: Data()
        )
        let view = MatchDetailView(match: record, onRematch: { _ in })

        XCTAssertEqual(view.durationText, "< 1 min")
    }
}
