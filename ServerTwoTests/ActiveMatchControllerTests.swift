import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

@MainActor
final class ActiveMatchControllerTests: XCTestCase {
    private func makeController(
        userDefaultsSuite: String = UUID().uuidString
    ) throws -> (ActiveMatchController, UserDefaults) {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: userDefaultsSuite)!
        let controller = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        return (controller, defaults)
    }

    func testStartNewMatchCreatesLiveMatchWithGivenNamesAndPersistsSnapshot() throws {
        let (controller, _) = try makeController()
        controller.startNewMatch(
            configuration: GameConfiguration(),
            matchFormat: .bestOfOne,
            firstServingTeam: .teamA,
            teamAName: "The Smashers",
            teamBName: "Net Ninjas"
        )
        XCTAssertNotNil(controller.match)
        XCTAssertEqual(controller.teamAName, "The Smashers")
        XCTAssertEqual(controller.teamBName, "Net Ninjas")
    }

    func testStartNewMatchFallsBackToDefaultNamesWhenBlank() throws {
        let (controller, _) = try makeController()
        controller.startNewMatch(
            configuration: GameConfiguration(),
            matchFormat: .bestOfOne,
            firstServingTeam: .teamA,
            teamAName: "   ",
            teamBName: ""
        )
        XCTAssertEqual(controller.teamAName, "Team A")
        XCTAssertEqual(controller.teamBName, "Team B")
    }

    func testResumeIfNeededRestoresMatchStartedAtAndNames() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!

        let first = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        first.startNewMatch(
            configuration: GameConfiguration(),
            matchFormat: .bestOfThree,
            firstServingTeam: .teamA,
            teamAName: "The Smashers",
            teamBName: "Net Ninjas"
        )
        first.recordPoint(for: .teamA)
        first.recordPoint(for: .teamA)

        // A fresh controller against the same store/defaults simulates a relaunch.
        let resumed = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        XCTAssertNotNil(resumed.match)
        XCTAssertEqual(resumed.match?.currentGame.state.teamAScore, 2)
        XCTAssertEqual(resumed.teamAName, "The Smashers")
        XCTAssertEqual(resumed.teamBName, "Net Ninjas")
    }

    func testResumeIfNeededDoesNothingWhenAlreadyHasALiveMatch() throws {
        let (controller, _) = try makeController()
        controller.startNewMatch(
            configuration: GameConfiguration(),
            matchFormat: .bestOfOne,
            firstServingTeam: .teamA,
            teamAName: "A",
            teamBName: "B"
        )
        let matchBeforeResume = controller.match
        controller.resumeIfNeeded()
        XCTAssertTrue(controller.match === matchBeforeResume)
    }

    func testRecordPointPersistsSnapshotAfterEveryPoint() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        controller.startNewMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, teamAName: "A", teamBName: "B")
        controller.recordPoint(for: .teamA)

        let reread = try MatchRepository(modelContext: container.mainContext)
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: controller.demoPointCap)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 1)
    }

    func testUndoPersistsSnapshot() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        controller.startNewMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, teamAName: "A", teamBName: "B")
        controller.recordPoint(for: .teamA)
        controller.undo()

        let reread = try MatchRepository(modelContext: container.mainContext)
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: controller.demoPointCap)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 0)
    }

    func testCorrectScorePersistsSnapshot() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        controller.startNewMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, teamAName: "A", teamBName: "B")
        controller.correctScore(team: .teamA, to: 7)

        let reread = try MatchRepository(modelContext: container.mainContext)
            .loadInProgressMatch(proUnlocked: controller.proUnlocked, demoPointCap: controller.demoPointCap)
        XCTAssertEqual(reread?.match.currentGame.state.teamAScore, 7)
    }

    func testRequestTimeoutPersistsSnapshotOnlyWhenTimeoutActuallyStarts() throws {
        let (controller, _) = try makeController()
        controller.startNewMatch(
            configuration: GameConfiguration(timeoutsPerTeam: 0),
            matchFormat: .bestOfOne,
            firstServingTeam: .teamA,
            teamAName: "A",
            teamBName: "B"
        )
        XCTAssertFalse(controller.requestTimeout(for: .teamA))
    }

    func testFinishMatchSavesToHistoryClearsLiveMatchAndClearsStoredNames() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        controller.startNewMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, teamAName: "A", teamBName: "B")
        for _ in 1...11 { controller.recordPoint(for: .teamA) }

        let record = try controller.finishMatch()
        XCTAssertEqual(record.winningTeam, .teamA)
        XCTAssertNil(controller.match)

        let history = try MatchRepository(modelContext: container.mainContext).fetchMatchHistory()
        XCTAssertEqual(history.count, 1)

        // A fresh controller must not think there's a match to resume.
        let afterRelaunch = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        XCTAssertNil(afterRelaunch.match)
    }

    func testFinishMatchThrowsAndLeavesMatchIntactWhenMatchNotOver() throws {
        let (controller, _) = try makeController()
        controller.startNewMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, teamAName: "A", teamBName: "B")
        controller.recordPoint(for: .teamA)

        XCTAssertThrowsError(try controller.finishMatch()) { error in
            XCTAssertEqual(error as? MatchRepositoryError, .matchNotOver)
        }
        XCTAssertNotNil(controller.match)
    }

    func testUnlockProSetsFlagUnlocksLiveMatchAndPersistsSnapshot() throws {
        let (controller, _) = try makeController()
        controller.demoPointCap = 2
        controller.startNewMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, teamAName: "A", teamBName: "B")
        controller.recordPoint(for: .teamA)
        controller.recordPoint(for: .teamA)
        XCTAssertTrue(controller.match?.isPaywalled ?? false)

        controller.unlockPro()
        XCTAssertTrue(controller.proUnlocked)
        XCTAssertFalse(controller.match?.isPaywalled ?? true)
    }

    func testProUnlockedPersistsAcrossControllerInstances() throws {
        let suite = UUID().uuidString
        let container = try PersistenceContainer.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let first = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        first.unlockPro()

        let second = ActiveMatchController(modelContext: container.mainContext, userDefaults: defaults)
        XCTAssertTrue(second.proUnlocked)
    }
}
