import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

@MainActor
final class OnboardingGateTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    func testNoPlayersMeansANewUser() throws {
        XCTAssertFalse(OnboardingView.returningUserExists(in: try makeContext()))
    }

    func testSavedPlayersWithoutMeAreNotAReturningUser() throws {
        let context = try makeContext()
        _ = try MatchRepository(modelContext: context).upsertSavedPlayer(name: "Sarah")
        XCTAssertFalse(OnboardingView.returningUserExists(in: context))
    }

    func testARestoredMePlayerMeansAReturningUser() throws {
        let context = try makeContext()
        let repository = MatchRepository(modelContext: context)
        let me = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
        try repository.setMePlayer(me)
        XCTAssertTrue(OnboardingView.returningUserExists(in: context))
    }
}
