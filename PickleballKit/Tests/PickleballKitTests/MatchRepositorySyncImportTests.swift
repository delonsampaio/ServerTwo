import XCTest
import SwiftData
@testable import PickleballKit

@MainActor
final class MatchRepositorySyncImportTests: XCTestCase {
    private var context: ModelContext!
    private var repository: MatchRepository!
    private var seen: SeenMatchIDStore!

    override func setUp() async throws {
        context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        seen = SeenMatchIDStore(suiteName: makeSyncSuite())
        repository = MatchRepository(modelContext: context, seenMatchIDs: seen)
    }

    private func counts() throws -> (matches: Int, sides: Int, games: Int, points: Int) {
        (
            try context.fetchCount(FetchDescriptor<MatchRecord>()),
            try context.fetchCount(FetchDescriptor<TeamSide>()),
            try context.fetchCount(FetchDescriptor<GameRecord>()),
            try context.fetchCount(FetchDescriptor<PointEvent>())
        )
    }

    // MARK: Import

    func testValidPayloadIsImportedWithGamesPointsNamesAndWinner() throws {
        let payload = SyncFixtures.payload(teamAName: "Ann & Bo", teamBName: "Cy")
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)

        let record = try XCTUnwrap(try repository.fetchMatchRecord(id: payload.id))
        XCTAssertEqual(record.id, payload.id)
        XCTAssertEqual(record.winningTeam, .teamA)
        XCTAssertEqual(record.matchFormat, .bestOfThree)
        XCTAssertEqual(record.startedAt, payload.startedAt)
        XCTAssertEqual(record.completedAt, payload.completedAt)
        XCTAssertEqual(record.configurationData, payload.configurationData)
        let sides = record.teamSides ?? []
        XCTAssertEqual(sides.first { $0.team == .teamA }?.displayName, "Ann & Bo")
        XCTAssertEqual(sides.first { $0.team == .teamB }?.displayName, "Cy")
        XCTAssertTrue(sides.allSatisfy { ($0.players ?? []).isEmpty }, "players stay unlinked")
        let games = (record.games ?? []).sorted { $0.gameNumber < $1.gameNumber }
        XCTAssertEqual(games.map(\.gameNumber), [1, 2, 3])
        XCTAssertEqual(games.map(\.teamAFinalScore), [11, 8, 11])
        XCTAssertEqual(games.map(\.teamBFinalScore), [9, 11, 4])
        XCTAssertEqual(games.map(\.winningTeam), [.teamA, .teamB, .teamA])
        XCTAssertEqual(games[0].completedAt, payload.games[0].completedAt)
        XCTAssertEqual(games.map { $0.orderedPoints.count }, [20, 19, 15])
        XCTAssertEqual(games[0].orderedPoints.map(\.sequenceNumber), Array(1...20))
        XCTAssertEqual(games[0].orderedPoints.last?.teamAScoreAfter, 11)
        XCTAssertTrue(seen.contains(payload.id))
    }

    func testBlankAndPlaceholderNamesStayPlaceholders() throws {
        let payload = SyncFixtures.payload(teamAName: "   ", teamBName: "Team B")
        _ = try repository.importSyncedMatch(payload)
        let sides = try XCTUnwrap(try repository.fetchMatchRecord(id: payload.id)?.teamSides)
        XCTAssertEqual(sides.first { $0.team == .teamA }?.displayName, "Team A")
        XCTAssertEqual(sides.first { $0.team == .teamB }?.displayName, "Team B")
    }

    func testNamesAreTrimmedStrippedOfControlCharactersAndCapped() {
        XCTAssertEqual(SyncedMatchValidator.sanitizedName("  Ann\n\tBo\u{7}  ", team: .teamA), "AnnBo")
        XCTAssertEqual(SyncedMatchValidator.sanitizedName("\n\t", team: .teamB), "Team B")
        XCTAssertEqual(SyncedMatchValidator.sanitizedName(String(repeating: "x", count: 200), team: .teamA).count, 64)
        // Capping must not leave trailing whitespace behind.
        XCTAssertEqual(
            SyncedMatchValidator.sanitizedName(String(repeating: "x", count: 63) + "   y", team: .teamA),
            String(repeating: "x", count: 63)
        )
    }

    func testStartAfterCompletionIsClamped() throws {
        var payload = SyncFixtures.payload()
        payload.startedAt = payload.completedAt.addingTimeInterval(500)
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
        XCTAssertEqual(try repository.fetchMatchRecord(id: payload.id)?.startedAt, payload.completedAt)
    }

    func testOutOfRangeGameCompletionDatesBecomeNil() throws {
        var payload = SyncFixtures.payload()
        payload.games[0].completedAt = payload.completedAt.addingTimeInterval(10)  // after the match
        payload.games[1].completedAt = payload.startedAt.addingTimeInterval(-10)  // before it
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
        let games = (try XCTUnwrap(try repository.fetchMatchRecord(id: payload.id)).games ?? []).sorted { $0.gameNumber < $1.gameNumber }
        XCTAssertNil(games[0].completedAt)
        XCTAssertNil(games[1].completedAt)
        XCTAssertNotNil(games[2].completedAt)
    }

    func testNonFiniteDatesAreRejected() throws {
        var payload = SyncFixtures.payload()
        payload.completedAt = Date(timeIntervalSinceReferenceDate: .nan)
        XCTAssertEqual(try repository.importSyncedMatch(payload), .rejected(.invalidDate))
    }

    // MARK: Idempotence

    func testAnExistingMatchIsADuplicateAndIsNeverOverwritten() throws {
        let payload = SyncFixtures.payload()
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
        // The user edited the match on the phone (first write wins).
        let record = try XCTUnwrap(try repository.fetchMatchRecord(id: payload.id))
        try repository.updateSides(
            of: record, teamA: [PlayerSlotEntry(name: "Edited")], teamB: []
        )
        let before = try counts()

        XCTAssertEqual(try repository.importSyncedMatch(payload), .duplicate)

        XCTAssertEqual(try counts().matches, before.matches)
        XCTAssertEqual(try repository.fetchMatchRecord(id: payload.id)?.teamSides?.first { $0.team == .teamA }?.displayName, "Edited")
    }

    func testAMatchOnlySeenBeforeIsADuplicate() throws {
        let payload = SyncFixtures.payload()
        seen.insert(payload.id)
        XCTAssertEqual(try repository.importSyncedMatch(payload), .duplicate)
        XCTAssertEqual(try counts().matches, 0)
    }

    func testDeletingAnImportedMatchThenResendingDoesNotBringItBack() throws {
        let payload = SyncFixtures.payload()
        _ = try repository.importSyncedMatch(payload)
        try repository.deleteMatch(try XCTUnwrap(try repository.fetchMatchRecord(id: payload.id)))
        XCTAssertEqual(try counts().matches, 0)

        XCTAssertEqual(try repository.importSyncedMatch(payload), .duplicate)
        XCTAssertEqual(try counts().matches, 0)
    }

    func testDeletingAMatchPlayedOnThePhoneRemembersItsID() throws {
        let record = try SyncFixtures.saveRealMatch(repository)
        let id = record.id
        try repository.deleteMatch(record)
        XCTAssertTrue(seen.contains(id))
    }

    func testDeletingAllHistoryRemembersEveryID() throws {
        let a = try SyncFixtures.saveRealMatch(repository).id
        let b = try SyncFixtures.saveRealMatch(repository).id
        try repository.deleteAllMatchHistory()
        XCTAssertTrue(seen.contains(a))
        XCTAssertTrue(seen.contains(b))
    }

    func testDeletingAMatchAlsoDeletesItsHiddenTwinsAndRemembersTheIDOnce() throws {
        let id = UUID()
        let visible = try SyncFixtures.saveRealMatch(repository, id: id, completedAt: SyncFixtures.t0)
        try SyncFixtures.saveRealMatch(repository, id: id, completedAt: SyncFixtures.t0)
        let other = try SyncFixtures.saveRealMatch(repository, completedAt: SyncFixtures.t0.addingTimeInterval(-50))
        XCTAssertEqual(try counts().matches, 3)

        try repository.deleteMatch(visible)

        XCTAssertEqual(try counts().matches, 1, "both rows with the id are gone")
        XCTAssertEqual(try repository.fetchMatchHistory().first?.id, other.id)
        XCTAssertEqual(seen.ids.filter { $0 == id }.count, 1)
        XCTAssertEqual(try counts().games, 1, "their games and points went with them")
    }

    // MARK: Versions

    func testANewerSchemaIsNotStoredNorMarkedSeen() throws {
        var payload = SyncFixtures.payload()
        payload.schemaVersion = SyncedMatchPayload.currentSchemaVersion + 1
        XCTAssertEqual(try repository.importSyncedMatch(payload), .unsupportedNewerSchema)
        XCTAssertEqual(try counts().matches, 0)
        XCTAssertFalse(seen.contains(payload.id), "it must be importable after the phone updates")
    }

    func testAnInvalidSchemaVersionIsRejected() throws {
        var payload = SyncFixtures.payload()
        payload.schemaVersion = 0
        XCTAssertEqual(try repository.importSyncedMatch(payload), .rejected(.invalidSchemaVersion))
    }

    // MARK: Validation

    private func assertRejected(
        _ reason: SyncedMatchRejection,
        file: StaticString = #filePath, line: UInt = #line,
        _ mutate: (inout SyncedMatchPayload) -> Void
    ) throws {
        var payload = SyncFixtures.payload()
        mutate(&payload)
        XCTAssertEqual(try repository.importSyncedMatch(payload), .rejected(reason), file: file, line: line)
        XCTAssertEqual(try counts().matches, 0, "a rejected match leaves nothing behind", file: file, line: line)
        XCTAssertFalse(seen.contains(payload.id), file: file, line: line)
    }

    func testEachValidationBoundRejects() throws {
        try assertRejected(.invalidMatchFormat) { $0.matchFormatRawValue = 4 }
        try assertRejected(.invalidConfiguration) { $0.configurationData = Data([1, 2]) }
        try assertRejected(.invalidConfiguration) {
            $0.configurationData = try! JSONEncoder().encode(GameConfiguration(timeoutsPerTeam: 11))
        }
        try assertRejected(.invalidConfiguration) {
            $0.configurationData = try! JSONEncoder().encode(GameConfiguration(timeoutsPerTeam: -1))
        }
        try assertRejected(.invalidWinner) { $0.winningTeamRawValue = "teamC" }
        try assertRejected(.invalidGameCount) { $0.games = [] }
        try assertRejected(.invalidGameCount) { $0.games += [SyncFixtures.game(4, 11, 3), SyncFixtures.game(5, 11, 3)] }
        try assertRejected(.invalidGameNumbers) { $0.games[1].number = 3; $0.games[2].number = 4 }
        try assertRejected(.invalidGameNumbers) { $0.games[0].number = 0 }
        try assertRejected(.invalidGameScore) { $0.games[0] = SyncFixtures.game(1, 10, 9) }       // nobody reached 11
        try assertRejected(.invalidGameScore) { $0.games[0] = SyncFixtures.game(1, 11, 10) }      // not win by two
        try assertRejected(.invalidGameScore) { $0.games[0] = SyncFixtures.game(1, 15, 10) }      // impossible overtime
        try assertRejected(.invalidGameScore) { $0.games[0] = SyncFixtures.game(1, 120, 118) }    // above 99
        try assertRejected(.invalidGameScore) { $0.games[0].winningTeamRawValue = Team.teamB.rawValue }
        try assertRejected(.invalidGameScore) { $0.games[0].teamAFinalScore = -11 }
        try assertRejected(.winnerMismatch) { $0.winningTeamRawValue = Team.teamB.rawValue }
        try assertRejected(.winnerMismatch) { $0.games.removeLast() }                             // 1-1, undecided
        try assertRejected(.gameAfterMatchDecided) {
            $0.games = [SyncFixtures.game(1, 11, 3), SyncFixtures.game(2, 11, 3), SyncFixtures.game(3, 11, 3)]
        }
    }

    func testEachPointLogBoundRejects() throws {
        try assertRejected(.invalidPoints) { $0.games[0].points.removeFirst() }                   // not from 1
        try assertRejected(.invalidPoints) { $0.games[0].points[3].sequenceNumber = 9 }           // gap
        try assertRejected(.invalidPoints) { $0.games[0].points[2].teamAScoreAfter = 0 }          // goes down
        try assertRejected(.invalidPoints) { $0.games[0].points[2].scoringTeamRawValue = "x" }
        try assertRejected(.invalidPoints) { $0.games[0].points[2].teamBScoreAfter = 100 }
        try assertRejected(.invalidPoints) { $0.games[0].points.removeLast() }                    // ends short of the final
        try assertRejected(.invalidPoints) {
            let extra = (0..<501).map {
                SyncedMatchPayload.Point(sequenceNumber: $0 + 1, scoringTeamRawValue: "teamA", teamAScoreAfter: 11, teamBScoreAfter: 9)
            }
            $0.games[0].points = extra
        }
    }

    func testAGameWithNoPointLogIsAccepted() throws {
        var payload = SyncFixtures.payload()
        for index in payload.games.indices { payload.games[index].points = [] }
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
    }

    func testAnOvertimeFinalIsAccepted() throws {
        var payload = SyncFixtures.payload()
        payload.games[0] = SyncFixtures.game(1, 13, 11)
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
    }

    /// Freeze is the one format whose overtime margin is not 2 (see
    /// `isCompletedGameScore`), so it must pass with a wider one.
    func testAFreezeOvertimeFinalWithAWiderMarginIsAccepted() throws {
        var payload = SyncFixtures.payload()
        payload.configurationData = try JSONEncoder().encode(GameConfiguration(scoringFormat: .rally(freeze: true)))
        payload.games[0] = SyncFixtures.game(1, 16, 12)
        XCTAssertEqual(try repository.importSyncedMatch(payload), .imported)
        // The same final is impossible without freeze.
        var strict = SyncFixtures.payload()
        strict.games[0] = SyncFixtures.game(1, 16, 12)
        XCTAssertEqual(try repository.importSyncedMatch(strict), .rejected(.invalidGameScore))
    }

    // MARK: The live phone match

    func testImportingNeverClearsTheInProgressSnapshot() throws {
        let live = PickleballMatch(
            configuration: GameConfiguration(), matchFormat: .bestOfOne,
            firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil
        )
        live.recordPoint(for: .teamA)
        try repository.saveInProgressSnapshot(for: live, startedAt: Date())

        XCTAssertEqual(try repository.importSyncedMatch(SyncFixtures.payload()), .imported)

        XCTAssertNotNil(try repository.loadInProgressMatch(proUnlocked: true, demoPointCap: nil),
                        "a watch match arriving must not erase the phone's crash recovery")
    }

    // MARK: History

    func testSaveCompletedMatchUsesTheGivenID() throws {
        let id = UUID()
        XCTAssertEqual(try SyncFixtures.saveRealMatch(repository, id: id).id, id)
    }

    func testHistoryCollapsesRowsSharingAnIDAndKeepsTheOneWithPlayers() throws {
        let id = UUID()
        let plain = try SyncFixtures.saveRealMatch(repository, id: id, completedAt: SyncFixtures.t0)
        let linked = try SyncFixtures.saveRealMatch(repository, id: id, completedAt: SyncFixtures.t0)
        let other = try SyncFixtures.saveRealMatch(repository, completedAt: SyncFixtures.t0.addingTimeInterval(-100))
        let ann = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Ann"))
        try repository.updateSides(of: linked, teamA: [PlayerSlotEntry(name: "Ann", savedPlayerID: ann.id)], teamB: [])
        XCTAssertNotNil(plain)

        let history = try repository.fetchMatchHistory()

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.map(\.id).filter { $0 == id }.count, 1)
        let kept = try XCTUnwrap(history.first { $0.id == id })
        XCTAssertTrue(kept === linked, "the edited row wins")
        XCTAssertEqual(history.last?.id, other.id, "the sort order is unchanged")
    }

    func testHistoryWithoutDuplicatesIsUnchanged() throws {
        try SyncFixtures.saveRealMatch(repository, completedAt: SyncFixtures.t0)
        try SyncFixtures.saveRealMatch(repository, completedAt: SyncFixtures.t0.addingTimeInterval(10))
        XCTAssertEqual(try repository.fetchMatchHistory().count, 2)
    }
}
