import XCTest
import SwiftData
@testable import PickleballKit

/// The guard against silent loss: the Watch deletes its only copy once the
/// phone acknowledges, and the phone acknowledges a REJECTED match too. So any
/// match the real engine can produce must pass the importer's validation. Each
/// case plays a real match through `PickleballMatch`, saves it like the Watch
/// does, sends it through the payload (including its JSON) and imports it.
@MainActor
final class SyncedMatchEngineTableTests: XCTestCase {
    private struct Case {
        let name: String
        let configuration: GameConfiguration
        let format: MatchFormat
        /// Who wins each game, in order, and whether it goes to overtime.
        let games: [(winner: Team, overtime: Bool)]
    }

    private static func cases() -> [Case] {
        var cases: [Case] = []
        let bo1: [(Team, Bool)] = [(.teamA, false)]
        let bo1Overtime: [(Team, Bool)] = [(.teamB, true)]
        let bo3: [(Team, Bool)] = [(.teamA, false), (.teamB, true), (.teamA, false)]
        let bo5: [(Team, Bool)] = [(.teamA, false), (.teamB, false), (.teamA, true), (.teamB, false), (.teamB, false)]
        let formats: [(MatchFormat, [(Team, Bool)])] = [(.bestOfOne, bo1), (.bestOfOne, bo1Overtime), (.bestOfThree, bo3), (.bestOfFive, bo5)]
        let scorings: [(String, ScoringFormat)] = [
            ("side-out", .sideOut), ("rally", .rally(freeze: false)), ("rally freeze", .rally(freeze: true))
        ]
        for (scoringName, scoring) in scorings {
            for mode in [PlayMode.doubles, .singles] {
                for target in [WinningScore.eleven, .fifteen, .twentyOne] {
                    for (format, games) in formats {
                        // The full cross product is wasteful; keep every
                        // scoring/mode/target once with each format shape.
                        cases.append(Case(
                            name: "\(scoringName) \(mode) to \(target.rawValue) best of \(format.rawValue) \(games.contains { $0.1 } ? "with overtime" : "plain")",
                            configuration: GameConfiguration(playMode: mode, scoringFormat: scoring, winningScore: target, winByTwo: true),
                            format: format,
                            games: games
                        ))
                    }
                }
            }
        }
        // Win by two off: the game simply ends at the target, a tie-break
        // "overtime" is a one-point win.
        for scoring in [ScoringFormat.sideOut, .rally(freeze: false)] {
            cases.append(Case(
                name: "no win-by-two \(scoring) best of 3",
                configuration: GameConfiguration(scoringFormat: scoring, winByTwo: false),
                format: .bestOfThree,
                games: [(.teamA, true), (.teamB, false), (.teamA, true)]
            ))
        }
        return cases
    }

    /// Taps toward exactly `a`-`b` without finishing the game: in side-out only
    /// the serving team scores, so the other team's tap just hands the serve over.
    private func drive(_ match: PickleballMatch, toA a: Int, b: Int) {
        var taps = 0
        while taps < 3000 {
            let state = match.currentGame.state
            let needsA = state.teamAScore < a, needsB = state.teamBScore < b
            guard needsA || needsB else { return }
            let team: Team
            if case .sideOut = match.configuration.scoringFormat {
                let serving = state.servingTeam
                let servingNeeds = serving == .teamA ? needsA : needsB
                team = servingNeeds ? serving : serving.opponent
            } else {
                team = needsA && (!needsB || state.teamAScore <= state.teamBScore) ? .teamA : .teamB
            }
            match.recordPoint(for: team)
            taps += 1
        }
        XCTFail("never reached \(a)-\(b)")
    }

    func testEveryRealMatchTheEngineCanPlayIsImported() throws {
        let cases = Self.cases()
        XCTAssertGreaterThan(cases.count, 70)
        var overtimeFinals = 0
        for item in cases {
            let source = MatchRepository(
                modelContext: ModelContext(try PersistenceContainer.makeInMemoryContainer()),
                seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite())
            )
            let phone = MatchRepository(
                modelContext: ModelContext(try PersistenceContainer.makeInMemoryContainer()),
                seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite())
            )
            let match = PickleballMatch(
                configuration: item.configuration, matchFormat: item.format,
                firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil
            )
            for game in item.games {
                guard !match.isMatchOver else { break }
                if game.overtime {
                    let tie = item.configuration.winningScore.rawValue - 1
                    drive(match, toA: tie, b: tie)
                }
                playOutGame(match, winner: game.winner)
            }
            XCTAssertTrue(match.isMatchOver, item.name)
            let record = try source.saveCompletedMatch(
                match, teamAName: "Team A", teamBName: "Team B",
                startedAt: Date().addingTimeInterval(-3600), gameCompletionDates: match.completedGames.map { _ in Date() }
            )
            let payload = try SyncedMatchPayload.decode(from: try SyncedMatchPayload(record: record).encoded())
            if payload.games.contains(where: { abs($0.teamAFinalScore - $0.teamBFinalScore) == 2 && max($0.teamAFinalScore, $0.teamBFinalScore) > item.configuration.winningScore.rawValue }) {
                overtimeFinals += 1
            }

            XCTAssertEqual(try phone.importSyncedMatch(payload), .imported, item.name)
        }
        XCTAssertGreaterThan(overtimeFinals, 10, "the table must really contain overtime finals")
    }

    func testAFreezeMatchEndsOnAServedPointAndIsImported() throws {
        // The freeze rule: a game can only be won on the winner's own serve, so
        // the final can sit above the target by more than the usual margin.
        let config = GameConfiguration(scoringFormat: .rally(freeze: true))
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        drive(match, toA: 10, b: 10)
        playOutGame(match, winner: .teamA)
        let repository = MatchRepository(
            modelContext: ModelContext(try PersistenceContainer.makeInMemoryContainer()),
            seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite())
        )
        let record = try repository.saveCompletedMatch(match, teamAName: "Team A", teamBName: "Team B", startedAt: Date())
        let game = try XCTUnwrap(SyncedMatchPayload(record: record).games.first)
        XCTAssertGreaterThanOrEqual(game.teamAFinalScore, 12, "it went past the target")
        let phone = MatchRepository(
            modelContext: ModelContext(try PersistenceContainer.makeInMemoryContainer()),
            seenMatchIDs: SeenMatchIDStore(suiteName: makeSyncSuite())
        )
        XCTAssertEqual(try phone.importSyncedMatch(SyncedMatchPayload(record: record)), .imported)
    }
}
