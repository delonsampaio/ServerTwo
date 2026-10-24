import XCTest
import SwiftData
@testable import PickleballKit

final class MatchRepositoryUpdateSidesTests: XCTestCase {
    private func makeRepository() throws -> (MatchRepository, ModelContext) {
        let context = ModelContext(try PersistenceContainer.makeInMemoryContainer())
        return (MatchRepository(modelContext: context), context)
    }

    private let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

    /// Team A wins 11-7 unless told otherwise. Sides are linked to the given
    /// players, named the way the app names them at save time.
    @discardableResult
    private func quickLog(
        _ repository: MatchRepository,
        teamA: [SavedPlayer] = [],
        teamB: [SavedPlayer] = [],
        teamAScore: Int = 11,
        teamBScore: Int = 7
    ) throws -> MatchRecord {
        try repository.saveQuickLoggedMatch(
            configuration: config,
            matchFormat: .bestOfOne,
            teamAName: TeamNaming.displayName(forPlayerNames: teamA.map(\.name), team: .teamA),
            teamBName: TeamNaming.displayName(forPlayerNames: teamB.map(\.name), team: .teamB),
            gameScores: [(teamAScore, teamBScore)],
            teamAPlayers: teamA,
            teamBPlayers: teamB
        )
    }

    private func side(_ team: Team, of match: MatchRecord) throws -> TeamSide {
        try XCTUnwrap((match.teamSides ?? []).first { $0.team == team })
    }

    private func entries(_ names: String...) -> [PlayerSlotEntry] {
        names.map { PlayerSlotEntry(name: $0) }
    }

    // MARK: Replace / fill / blank

    func testReplacesAWrongPlayerAndRebuildsTheDisplayName() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let bob = try XCTUnwrap(repository.upsertSavedPlayer(name: "Bob"))
        let sue = try XCTUnwrap(repository.upsertSavedPlayer(name: "Sue"))
        let match = try quickLog(repository, teamA: [mike], teamB: [bob])

        try repository.updateSides(
            of: match,
            teamA: entries("Mike"),
            teamB: [PlayerSlotEntry(name: "Sue", savedPlayerID: sue.id)]
        )

        let b = try side(.teamB, of: match)
        XCTAssertEqual(b.displayName, "Sue")
        XCTAssertEqual(b.players?.map(\.id), [sue.id])
        XCTAssertEqual(try side(.teamA, of: match).displayName, "Mike")
    }

    func testFillsABlankSideWithTwoPlayers() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let match = try quickLog(repository, teamA: [mike], teamB: [])
        XCTAssertEqual(try side(.teamB, of: match).displayName, "Team B")

        try repository.updateSides(of: match, teamA: entries("Mike"), teamB: entries("  Bob ", "Sue"))

        let b = try side(.teamB, of: match)
        XCTAssertEqual(b.displayName, "Bob & Sue")
        XCTAssertEqual(Set(b.players?.map(\.name) ?? []), ["Bob", "Sue"])
    }

    func testBlankingOutAPlayerFallsBackToTheTeamNameAndClearsPlayers() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let bob = try XCTUnwrap(repository.upsertSavedPlayer(name: "Bob"))
        let match = try quickLog(repository, teamA: [mike], teamB: [bob])

        try repository.updateSides(of: match, teamA: entries("Mike"), teamB: entries("   "))

        let b = try side(.teamB, of: match)
        XCTAssertEqual(b.displayName, "Team B")
        XCTAssertTrue((b.players ?? []).isEmpty)
    }

    func testBlankingTheFirstSlotOfADoublesSideKeepsOnlyTheSecondPlayerWithoutAStraySeparator() throws {
        let (repository, _) = try makeRepository()
        let a1 = try XCTUnwrap(repository.upsertSavedPlayer(name: "Ann"))
        let a2 = try XCTUnwrap(repository.upsertSavedPlayer(name: "Al"))
        let match = try quickLog(repository, teamA: [a1, a2])

        try repository.updateSides(of: match, teamA: entries("", "Al"), teamB: entries("Bob"))

        XCTAssertEqual(try side(.teamA, of: match).displayName, "Al")
    }

    func testLegacyMatchWithNilPlayersGetsPlayersLinked() throws {
        let (repository, context) = try makeRepository()
        // A legacy match: free-text names, no linked players at all.
        let match = try repository.saveQuickLoggedMatch(
            configuration: config, matchFormat: .bestOfOne,
            teamAName: "Mike", teamBName: "Bob", gameScores: [(11, 7)]
        )
        for s in match.teamSides ?? [] { s.players = nil }
        try context.save()

        try repository.updateSides(of: match, teamA: entries("Mike"), teamB: entries("Sue"))

        XCTAssertEqual(try side(.teamA, of: match).players?.map(\.name), ["Mike"])
        XCTAssertEqual(try side(.teamB, of: match).players?.map(\.name), ["Sue"])
        XCTAssertEqual(try side(.teamB, of: match).displayName, "Sue")
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        XCTAssertEqual(repository.myResult(for: mike, in: match), true)
    }

    // MARK: Duplicates

    func testTheSamePlayerTwiceInOneTeamIsRejected() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let match = try quickLog(repository, teamA: [mike])

        XCTAssertThrowsError(try repository.updateSides(
            of: match,
            teamA: [PlayerSlotEntry(name: "Mike", savedPlayerID: mike.id), PlayerSlotEntry(name: "Mike", savedPlayerID: mike.id)],
            teamB: []
        )) { XCTAssertEqual($0 as? MatchRepositoryError, .duplicatePlayer("Mike")) }
    }

    func testTheSamePlayerOnBothTeamsIsRejected() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let match = try quickLog(repository, teamA: [mike])

        XCTAssertThrowsError(try repository.updateSides(
            of: match,
            teamA: [PlayerSlotEntry(name: "Mike", savedPlayerID: mike.id)],
            teamB: [PlayerSlotEntry(name: "Mike", savedPlayerID: mike.id)]
        )) { XCTAssertEqual($0 as? MatchRepositoryError, .duplicatePlayer("Mike")) }
    }

    func testACaseInsensitiveTypedDuplicateIsRejectedAndNothingIsCreatedOrChanged() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let match = try quickLog(repository, teamA: [mike])

        // "Zed" is new; "mike" duplicates the saved "Mike" typed on the other team.
        XCTAssertThrowsError(try repository.updateSides(
            of: match, teamA: entries("Mike"), teamB: entries("mike", "Zed")
        )) { XCTAssertEqual($0 as? MatchRepositoryError, .duplicatePlayer("mike")) }

        XCTAssertEqual(try repository.fetchAllSavedPlayers().map(\.name), ["Mike"], "a rejected edit must not create Zed")
        XCTAssertEqual(try side(.teamA, of: match).displayName, "Mike")
        XCTAssertEqual(try side(.teamB, of: match).displayName, "Team B")
    }

    func testTwoIdenticalNewTypedNamesAreRejected() throws {
        let (repository, _) = try makeRepository()
        let match = try quickLog(repository)
        XCTAssertThrowsError(try repository.updateSides(of: match, teamA: entries("Zed", " zed "), teamB: [])) {
            XCTAssertEqual($0 as? MatchRepositoryError, .duplicatePlayer("zed"))
        }
        XCTAssertTrue(try repository.fetchAllSavedPlayers().isEmpty)
    }

    func testMoreThanTwoPlayersOnASideIsRejected() throws {
        let (repository, _) = try makeRepository()
        let match = try quickLog(repository)
        XCTAssertThrowsError(try repository.updateSides(of: match, teamA: entries("A", "B", "C"), teamB: [])) {
            XCTAssertEqual($0 as? MatchRepositoryError, .tooManyPlayers)
        }
    }

    // MARK: Typed names

    func testATypedNameCreatesASavedPlayerOnceAndLaterLinksTheExistingOne() throws {
        let (repository, _) = try makeRepository()
        let first = try quickLog(repository)
        let second = try quickLog(repository)

        try repository.updateSides(of: first, teamA: entries("Newbie"), teamB: [])
        try repository.updateSides(of: second, teamA: entries("newbie"), teamB: [])

        let all = try repository.fetchAllSavedPlayers()
        XCTAssertEqual(all.map(\.name), ["Newbie"])
        XCTAssertEqual(try side(.teamA, of: first).players?.first?.id, try side(.teamA, of: second).players?.first?.id)
        XCTAssertEqual(try side(.teamA, of: second).displayName, "Newbie", "the canonical saved casing is used")
    }

    func testASelectedIdWhoseNameWasEditedIsNotTrustedAndTheTypedNameWins() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let match = try quickLog(repository, teamA: [mike])

        // Same rule as MatchSetupView.resolvedPlayer: a stale selection must
        // not override what is actually in the field.
        try repository.updateSides(of: match, teamA: [PlayerSlotEntry(name: "Zed", savedPlayerID: mike.id)], teamB: [])

        XCTAssertEqual(try side(.teamA, of: match).displayName, "Zed")
    }

    func testTwoSavedPlayersSharingANameAreToldApartByTheSelectedIdInBothOrders() throws {
        let (repository, context) = try makeRepository()
        let mike1 = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let mike2 = SavedPlayer(name: "Mike")
        context.insert(mike2)
        try context.save()
        let match = try quickLog(repository, teamA: [mike1])

        // Picking either one must stick, whichever the unsorted fetch returns
        // first: a name lookup alone would always give the same one.
        try repository.updateSides(of: match, teamA: [PlayerSlotEntry(name: "Mike", savedPlayerID: mike2.id)], teamB: [])
        XCTAssertEqual(try side(.teamA, of: match).players?.map(\.id), [mike2.id])
        try repository.updateSides(of: match, teamA: [PlayerSlotEntry(name: "Mike", savedPlayerID: mike1.id)], teamB: [])
        XCTAssertEqual(try side(.teamA, of: match).players?.map(\.id), [mike1.id])
    }

    func testAFailureAfterNewPlayersAreInsertedLeavesNoOrphanAndNoSideChange() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let match = try quickLog(repository, teamA: [mike])
        struct Boom: Error {}

        XCTAssertThrowsError(try repository.updateSides(
            of: match, teamA: entries("Zed", "Amy"), teamB: entries("Quinn"), beforeSave: { throw Boom() }
        ))

        XCTAssertEqual(try repository.fetchAllSavedPlayers().map(\.name), ["Mike"], "no orphan Zed/Amy/Quinn")
        XCTAssertEqual(try side(.teamA, of: match).displayName, "Mike")
        XCTAssertEqual(try side(.teamA, of: match).players?.map(\.id), [mike.id])
        XCTAssertEqual(try side(.teamB, of: match).displayName, "Team B")
    }

    // MARK: Stats follow

    func testMovingMeToTheOtherTeamFlipsTheResultAndTheFallbackNeverMatchesAfterwards() throws {
        let (repository, _) = try makeRepository()
        let me = try XCTUnwrap(repository.upsertSavedPlayer(name: "Me"))
        let bob = try XCTUnwrap(repository.upsertSavedPlayer(name: "Bob"))
        let match = try quickLog(repository, teamA: [me], teamB: [bob])   // A wins
        XCTAssertEqual(repository.myResult(for: me, in: match), true)

        try repository.updateSides(of: match, teamA: entries("Bob"), teamB: entries("Me"))

        XCTAssertEqual(repository.myResult(for: me, in: match), false)
        XCTAssertEqual(repository.myResult(for: bob, in: match), true)
        let record = repository.personalRecord(for: me, in: [match])
        XCTAssertEqual(record.wins, 0)
        XCTAssertEqual(record.losses, 1)
        XCTAssertEqual(record.pointsFor, 7)
        XCTAssertEqual(record.pointsAgainst, 11)
    }

    func testChemistryUpdatesWhenAPartnerBecomesAnOpponent() throws {
        let (repository, _) = try makeRepository()
        let me = try XCTUnwrap(repository.upsertSavedPlayer(name: "Me"))
        let pal = try XCTUnwrap(repository.upsertSavedPlayer(name: "Pal"))
        let x = try XCTUnwrap(repository.upsertSavedPlayer(name: "X"))
        let match = try quickLog(repository, teamA: [me, pal], teamB: [x])

        var chem = repository.chemistry(between: me, and: pal, in: [match])
        XCTAssertEqual(chem.asPartner?.wins, 1)
        XCTAssertNil(chem.asOpponent)

        try repository.updateSides(of: match, teamA: entries("Me", "X"), teamB: entries("Pal"))

        chem = repository.chemistry(between: me, and: pal, in: [match])
        XCTAssertNil(chem.asPartner)
        XCTAssertEqual(chem.asOpponent?.wins, 1)
    }

    func testABlankedSideNamedTeamANeverMatchesASavedPlayerNamedTeamA() throws {
        let (repository, _) = try makeRepository()
        let teamAPlayer = try XCTUnwrap(repository.upsertSavedPlayer(name: "Team A"))
        let bob = try XCTUnwrap(repository.upsertSavedPlayer(name: "Bob"))
        let match = try quickLog(repository, teamA: [bob], teamB: [])

        try repository.updateSides(of: match, teamA: entries(""), teamB: entries("Bob"))

        XCTAssertEqual(try side(.teamA, of: match).displayName, "Team A")
        XCTAssertNil(repository.myResult(for: teamAPlayer, in: match), "the placeholder name is not a player")
        XCTAssertEqual(repository.myResult(for: bob, in: match), false)
    }

    func testALegacyMatchWithAPlaceholderSideNameDoesNotMatchAPlayerNamedLikeIt() throws {
        let (repository, context) = try makeRepository()
        let teamBPlayer = try XCTUnwrap(repository.upsertSavedPlayer(name: "Team B"))
        let match = try repository.saveQuickLoggedMatch(
            configuration: config, matchFormat: .bestOfOne,
            teamAName: "Mike", teamBName: "Team B", gameScores: [(11, 7)]
        )
        for s in match.teamSides ?? [] { s.players = nil }
        try context.save()

        XCTAssertNil(repository.myResult(for: teamBPlayer, in: match))
    }

    // MARK: Untouched

    func testScoresWinnerGamesAndConfigurationAreUntouched() throws {
        let (repository, _) = try makeRepository()
        let mike = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let match = try quickLog(repository, teamA: [mike], teamB: [])
        let configurationBefore = match.configurationData
        let gameIDsBefore = (match.games ?? []).map(\.id)

        try repository.updateSides(of: match, teamA: entries("Bob"), teamB: entries("Sue"))

        XCTAssertEqual(match.winningTeam, .teamA)
        XCTAssertEqual(match.configurationData, configurationBefore)
        XCTAssertEqual((match.games ?? []).map(\.id), gameIDsBefore)
        let game = try XCTUnwrap(match.games?.first)
        XCTAssertEqual(game.teamAFinalScore, 11)
        XCTAssertEqual(game.teamBFinalScore, 7)
        XCTAssertEqual(try repository.fetchMatchHistory().count, 1)
    }

    func testAPointByPointMatchKeepsItsPointLog() throws {
        let (repository, _) = try makeRepository()
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        playOutGame(match, winner: .teamA)
        let record = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())
        let pointsBefore = (record.games ?? []).flatMap { $0.points ?? [] }.count
        XCTAssertGreaterThan(pointsBefore, 0)

        try repository.updateSides(of: record, teamA: entries("Mike"), teamB: entries("Bob"))

        XCTAssertEqual((record.games ?? []).flatMap { $0.points ?? [] }.count, pointsBefore)
    }

    func testTwoSavedPlayersSharingANamePickedExplicitlyOnOpposingTeamsAreAllowed() throws {
        let (repository, context) = try makeRepository()
        let mike1 = try XCTUnwrap(repository.upsertSavedPlayer(name: "Mike"))
        let mike2 = SavedPlayer(name: "Mike")
        context.insert(mike2)
        try context.save()
        let match = try quickLog(repository)

        try repository.updateSides(
            of: match,
            teamA: [PlayerSlotEntry(name: "Mike", savedPlayerID: mike1.id)],
            teamB: [PlayerSlotEntry(name: "Mike", savedPlayerID: mike2.id)]
        )

        XCTAssertEqual(try side(.teamA, of: match).players?.map(\.id), [mike1.id])
        XCTAssertEqual(try side(.teamB, of: match).players?.map(\.id), [mike2.id])
    }

    func testATypedNameWithTrailingSpaceDuplicatesTheSamePickedPlayer() throws {
        let (repository, _) = try makeRepository()
        let delon = try XCTUnwrap(repository.upsertSavedPlayer(name: "Delon"))
        let match = try quickLog(repository)
        XCTAssertThrowsError(try repository.updateSides(
            of: match,
            teamA: [PlayerSlotEntry(name: "Delon", savedPlayerID: delon.id)],
            teamB: entries("delon ")
        )) { XCTAssertEqual($0 as? MatchRepositoryError, .duplicatePlayer("delon")) }
    }

    func testARejectedEditCreatesNoSavedPlayer() throws {
        // Duplicates are rejected before anything is created.
        let (repository, _) = try makeRepository()
        let match = try quickLog(repository)
        XCTAssertThrowsError(try repository.updateSides(of: match, teamA: entries("Zed"), teamB: entries("zed")))
        XCTAssertTrue(try repository.fetchAllSavedPlayers().isEmpty)
        XCTAssertEqual(try side(.teamA, of: match).displayName, "Team A")
    }

    // MARK: orderedPlayers

    func testOrderedPlayersFollowTheDisplayNameNotTheRelationshipOrder() throws {
        let (repository, _) = try makeRepository()
        let ann = try XCTUnwrap(repository.upsertSavedPlayer(name: "Ann"))
        let al = try XCTUnwrap(repository.upsertSavedPlayer(name: "Al"))
        let match = try quickLog(repository, teamA: [al, ann])   // relationship order: Al, Ann
        let a = try side(.teamA, of: match)
        a.displayName = "Ann & Al"
        XCTAssertEqual(a.orderedPlayers.map(\.name), ["Ann", "Al"])
    }

    func testOrderedPlayersMatchNamesCaseInsensitivelyAndKeepUnmatchedOnesAfterwards() throws {
        let (repository, _) = try makeRepository()
        let ann = try XCTUnwrap(repository.upsertSavedPlayer(name: "Ann"))
        let renamed = try XCTUnwrap(repository.upsertSavedPlayer(name: "Renamed Later"))
        let al = try XCTUnwrap(repository.upsertSavedPlayer(name: "Al"))
        let match = try quickLog(repository, teamA: [renamed, ann, al])
        let a = try side(.teamA, of: match)
        a.displayName = "al & ANN"
        XCTAssertEqual(a.orderedPlayers.map(\.name), ["Al", "Ann", "Renamed Later"])
    }

    func testOrderedPlayersOfASideWithoutPlayersIsEmpty() throws {
        let (repository, _) = try makeRepository()
        let match = try quickLog(repository)
        XCTAssertTrue(try side(.teamA, of: match).orderedPlayers.isEmpty)
    }

    func testSavingKeepsSlotOrderInTheDisplayName() throws {
        let (repository, _) = try makeRepository()
        let match = try quickLog(repository)
        try repository.updateSides(of: match, teamA: entries("Zed", "Amy"), teamB: [])
        XCTAssertEqual(try side(.teamA, of: match).displayName, "Zed & Amy")
        XCTAssertEqual(try side(.teamA, of: match).orderedPlayers.map(\.name), ["Zed", "Amy"])
    }

    // MARK: Display-name rules (single source of truth)

    func testDisplayNameRules() {
        XCTAssertEqual(TeamNaming.displayName(forPlayerNames: ["Mike", "Bob"], team: .teamA), "Mike & Bob")
        XCTAssertEqual(TeamNaming.displayName(forPlayerNames: [" Mike ", "  "], team: .teamA), "Mike")
        XCTAssertEqual(TeamNaming.displayName(forPlayerNames: ["", "Bob"], team: .teamB), "Bob")
        XCTAssertEqual(TeamNaming.displayName(forPlayerNames: [], team: .teamA), "Team A")
        XCTAssertEqual(TeamNaming.displayName(forPlayerNames: ["  ", ""], team: .teamB), "Team B")
        XCTAssertEqual(TeamNaming.joinedName(["", ""]), "")
        XCTAssertEqual(TeamNaming.placeholderName(for: .teamA), "Team A")
    }
}
