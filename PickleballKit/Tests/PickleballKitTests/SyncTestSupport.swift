import XCTest
import SwiftData
import os
@testable import PickleballKit

/// Shared fixtures for the Watch to phone sync tests.
enum SyncFixtures {
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A point log that ends exactly on `a`-`b`, alternating the scorers while
    /// both still have points to win (the engine's real order does not matter
    /// to the importer; only counts, order and the final score do).
    static func points(a: Int, b: Int) -> [SyncedMatchPayload.Point] {
        var points: [SyncedMatchPayload.Point] = []
        var scoreA = 0, scoreB = 0
        while scoreA < a || scoreB < b {
            let teamAScores = (scoreA < a && scoreB >= b) || (scoreA < a && scoreA <= scoreB)
            if teamAScores { scoreA += 1 } else { scoreB += 1 }
            points.append(.init(
                sequenceNumber: points.count + 1,
                scoringTeamRawValue: teamAScores ? Team.teamA.rawValue : Team.teamB.rawValue,
                teamAScoreAfter: scoreA,
                teamBScoreAfter: scoreB
            ))
        }
        return points
    }

    static func game(_ number: Int, _ a: Int, _ b: Int, completedAt: Date? = nil) -> SyncedMatchPayload.Game {
        .init(
            number: number,
            teamAFinalScore: a,
            teamBFinalScore: b,
            winningTeamRawValue: (a > b ? Team.teamA : Team.teamB).rawValue,
            completedAt: completedAt,
            points: points(a: a, b: b)
        )
    }

    /// Best of 3, doubles side-out to 11 win by 2: A wins 11-9, loses 8-11, wins 11-4.
    static func payload(
        id: UUID = UUID(),
        teamAName: String = "Team A",
        teamBName: String = "Team B"
    ) -> SyncedMatchPayload {
        let configuration = try! JSONEncoder().encode(GameConfiguration())
        return SyncedMatchPayload(
            id: id,
            startedAt: t0,
            completedAt: t0.addingTimeInterval(1800),
            matchFormatRawValue: MatchFormat.bestOfThree.rawValue,
            configurationData: configuration,
            winningTeamRawValue: Team.teamA.rawValue,
            teamAName: teamAName,
            teamBName: teamBName,
            games: [
                game(1, 11, 9, completedAt: t0.addingTimeInterval(600)),
                game(2, 8, 11, completedAt: t0.addingTimeInterval(1200)),
                game(3, 11, 4, completedAt: t0.addingTimeInterval(1800))
            ]
        )
    }

    /// A real finished best-of-1 saved through the repository.
    @MainActor
    @discardableResult
    static func saveRealMatch(
        _ repository: MatchRepository,
        winner: Team = .teamA,
        id: UUID = UUID(),
        completedAt: Date = Date()
    ) throws -> MatchRecord {
        let match = PickleballMatch(
            configuration: GameConfiguration(), matchFormat: .bestOfOne,
            firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil
        )
        playOutGame(match, winner: winner)
        return try repository.saveCompletedMatch(
            match, teamAName: "Team A", teamBName: "Team B",
            startedAt: completedAt.addingTimeInterval(-600), completedAt: completedAt,
            gameCompletionDates: [completedAt], id: id
        )
    }
}

/// A throwaway defaults suite per test, cleaned up afterwards.
extension XCTestCase {
    func makeSyncSuite() -> String {
        let suite = "SyncTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return suite
    }
}

@MainActor
final class FakeWatchTransport: WatchSyncTransport {
    var isActivated = true
    var outstanding: Set<UUID> = []
    private(set) var sent: [SyncedMatchMessage] = []
    private(set) var started = false
    private var onActivated: (@MainActor @Sendable () -> Void)?
    private var onAcknowledged: (@MainActor @Sendable (UUID) -> Void)?
    private var onPhoneState: (@MainActor @Sendable (PhoneStateContext) -> Void)?

    func hasOutstandingTransfer(forMatchID id: UUID) -> Bool { outstanding.contains(id) }
    func send(_ message: SyncedMatchMessage) { sent.append(message) }

    func start(
        onActivated: @escaping @MainActor @Sendable () -> Void,
        onAcknowledged: @escaping @MainActor @Sendable (UUID) -> Void,
        onPhoneState: @escaping @MainActor @Sendable (PhoneStateContext) -> Void
    ) {
        started = true
        self.onPhoneState = onPhoneState
        self.onActivated = onActivated
        self.onAcknowledged = onAcknowledged
    }

    func simulateActivation() { onActivated?() }
    func simulateAcknowledgement(_ id: UUID) { onAcknowledged?(id) }
    func simulatePhoneState(_ context: PhoneStateContext) { onPhoneState?(context) }
}

final class FakeAcknowledger: PhoneSyncAcknowledging {
    private let lock = OSAllocatedUnfairLock<[UUID]>(initialState: [])
    func acknowledge(matchID: UUID) { lock.withLock { $0.append(matchID) } }
    var acknowledged: [UUID] { lock.withLock { $0 } }
}
