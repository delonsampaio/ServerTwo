import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

private typealias State = PickleballActivityAttributes.ContentState

/// Records every ActivityKit-shaped call so the controller can be tested with
/// no ActivityKit involved (and so a unit test never puts a real Live Activity
/// on the simulator).
@MainActor
final class RecordingLiveActivityHost: LiveActivityHosting {
    enum Event: Hashable {
        case request(PickleballActivityAttributes, PickleballActivityAttributes.ContentState)
        case update(handle: Int, PickleballActivityAttributes.ContentState)
        case end(handle: Int, PickleballActivityAttributes.ContentState?, LiveActivityDismissal)
    }

    struct RequestFailure: Error {}

    var areActivitiesEnabled = true
    var failRequests = false
    private(set) var events: [Event] = []
    /// The staleDate of every request and update, in order.
    private(set) var staleDates: [Date?] = []
    private(set) var handles: [RecordingHandle] = []
    /// What `runningActivities` reports, e.g. a leftover from an earlier launch.
    var running: [RecordingHandle] = []

    var runningActivities: [any LiveActivityHandle] { running }

    func makeHandle(attributes: PickleballActivityAttributes) -> RecordingHandle {
        let handle = RecordingHandle(id: handles.count, attributes: attributes, host: self)
        handles.append(handle)
        return handle
    }

    func request(
        attributes: PickleballActivityAttributes,
        state: PickleballActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> any LiveActivityHandle {
        events.append(.request(attributes, state))
        staleDates.append(staleDate)
        if failRequests { throw RequestFailure() }
        let handle = makeHandle(attributes: attributes)
        running.append(handle)
        return handle
    }

    fileprivate func record(_ event: Event, staleDate: Date? = nil) {
        events.append(event)
        if case .update = event { staleDates.append(staleDate) }
    }

    var requests: [Event] { events.filter { if case .request = $0 { true } else { false } } }
    var updates: [Event] { events.filter { if case .update = $0 { true } else { false } } }
    var ends: [Event] { events.filter { if case .end = $0 { true } else { false } } }
}

@MainActor
final class RecordingHandle: LiveActivityHandle {
    let id: Int
    let attributes: PickleballActivityAttributes
    private unowned let host: RecordingLiveActivityHost

    init(id: Int, attributes: PickleballActivityAttributes, host: RecordingLiveActivityHost) {
        self.id = id
        self.attributes = attributes
        self.host = host
    }

    func update(_ state: PickleballActivityAttributes.ContentState, staleDate: Date?) async {
        host.record(.update(handle: id, state), staleDate: staleDate)
    }

    func end(_ finalState: PickleballActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async {
        host.record(.end(handle: id, finalState, dismissal))
        host.running.removeAll { $0.id == id }
    }
}

// MARK: - State mapping

@MainActor
final class LiveActivityStateMappingTests: XCTestCase {
    private func makeMatch(
        _ configuration: GameConfiguration = GameConfiguration(),
        format: MatchFormat = .bestOfOne,
        firstServer: Team = .teamA
    ) -> PickleballMatch {
        PickleballMatch(
            configuration: configuration, matchFormat: format,
            firstServingTeam: firstServer, proUnlocked: true, demoPointCap: nil
        )
    }

    func testDoublesSideOutMapsScoresServingTeamAndServerNumber() {
        let match = makeMatch(GameConfiguration(playMode: .doubles, scoringFormat: .sideOut), firstServer: .teamB)
        match.recordPoint(for: .teamB)
        match.recordPoint(for: .teamB)
        let state = State(match: match)
        XCTAssertEqual(state.teamAScore, 0)
        XCTAssertEqual(state.teamBScore, 2)
        XCTAssertEqual(state.servingTeamRawValue, "teamB")
        // A doubles game starts with the serving team on its 2nd server.
        XCTAssertEqual(state.serverNumber, 2)
        XCTAssertFalse(state.isMatchOver)
    }

    func testServerNumberFollowsSideOutsAndTheSecondServer() {
        let match = makeMatch(GameConfiguration(playMode: .doubles, scoringFormat: .sideOut))
        // Team A starts serving as server 2. Team B winning the rally is a side out:
        // team B serves as server 1.
        match.recordPoint(for: .teamB)
        XCTAssertEqual(State(match: match).servingTeamRawValue, "teamB")
        XCTAssertEqual(State(match: match).serverNumber, 1)
        // Team A winning that rally hands the serve to team B's second server.
        match.recordPoint(for: .teamA)
        XCTAssertEqual(State(match: match).servingTeamRawValue, "teamB")
        XCTAssertEqual(State(match: match).serverNumber, 2)
    }

    func testSinglesHasNoServerNumber() {
        let match = makeMatch(GameConfiguration(playMode: .singles, scoringFormat: .sideOut))
        XCTAssertNil(State(match: match).serverNumber)
    }

    func testRallyScoringHasNoServerNumberWithOrWithoutFreeze() {
        for freeze in [false, true] {
            let match = makeMatch(GameConfiguration(playMode: .doubles, scoringFormat: .rally(freeze: freeze)))
            XCTAssertNil(State(match: match).serverNumber, "rally freeze=\(freeze)")
        }
    }

    func testGamesWonAreCarriedInABestOfThreeAndScoresResetForTheNextGame() {
        let match = makeMatch(format: .bestOfThree)
        var taps = 0
        while match.completedGames.isEmpty, taps < 200 {
            match.recordPoint(for: .teamA)
            taps += 1
        }
        let state = State(match: match)
        XCTAssertEqual(state.teamAGamesWon, 1)
        XCTAssertEqual(state.teamBGamesWon, 0)
        XCTAssertEqual(state.teamAScore, 0, "a new game starts at 0-0")
        XCTAssertEqual(state.teamBScore, 0)
        XCTAssertFalse(state.isMatchOver)
    }

    func testMatchOverFlipsWhenTheLastGameIsWon() {
        let match = makeMatch(format: .bestOfOne)
        var taps = 0
        while !match.isMatchOver, taps < 200 {
            match.recordPoint(for: .teamA)
            taps += 1
        }
        let state = State(match: match)
        XCTAssertTrue(state.isMatchOver)
        XCTAssertEqual(state.teamAGamesWon, 1)
    }

    func testStaticAttributesCarryNamesAndTheSharedFormatSummary() {
        let config = GameConfiguration(playMode: .doubles, scoringFormat: .sideOut)
        let match = makeMatch(config, format: .bestOfThree)
        let attributes = PickleballActivityAttributes(match: match, teamAName: "Ann & Bo", teamBName: "Cy & Di")
        XCTAssertEqual(attributes.teamAName, "Ann & Bo")
        XCTAssertEqual(attributes.teamBName, "Cy & Di")
        XCTAssertEqual(attributes.matchFormatSummary, "Doubles • Best of 3")
        XCTAssertTrue(attributes.showsGamesWon)
    }

    func testSinglesBestOfOneRallySummaryHidesGamesWon() {
        let config = GameConfiguration(playMode: .singles, scoringFormat: .rally(freeze: false))
        let match = makeMatch(config, format: .bestOfOne)
        let attributes = PickleballActivityAttributes(match: match, teamAName: "A", teamBName: "B")
        XCTAssertEqual(attributes.matchFormatSummary, "Singles • Best of 1 • Rally")
        XCTAssertFalse(attributes.showsGamesWon)
    }
}

// MARK: - Controller (with a recording host)

@MainActor
final class LiveActivityControllerTests: XCTestCase {
    private let attributes = PickleballActivityAttributes(
        teamAName: "A", teamBName: "B", matchFormatSummary: "Doubles • Best of 1", showsGamesWon: false
    )

    private func state(a: Int = 0, b: Int = 0, serving: String = "teamA", server: Int? = 1, over: Bool = false) -> State {
        State(
            teamAScore: a, teamBScore: b, teamAGamesWon: 0, teamBGamesWon: 0,
            servingTeamRawValue: serving, serverNumber: server, isMatchOver: over
        )
    }

    private func makeController() -> (LiveActivityController, RecordingLiveActivityHost) {
        let host = RecordingLiveActivityHost()
        return (LiveActivityController(host: host), host)
    }

    func testBeginRequestsExactlyOneActivityWithTheStateAndAttributes() async {
        let (controller, host) = makeController()
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        XCTAssertEqual(host.events, [.request(attributes, state())])
    }

    func testUpdateOnlyForMeaningfulChanges() async {
        let (controller, host) = makeController()
        controller.begin(attributes: attributes, state: state())
        controller.update(state())            // identical: ignored
        controller.update(state(a: 1))        // score
        controller.update(state(a: 1))        // identical again: ignored
        controller.update(state(a: 1, server: 2))   // server number
        controller.update(state(a: 1, serving: "teamB", server: 1)) // serving team
        await controller.waitUntilIdle()
        XCTAssertEqual(host.updates.count, 3)
        XCTAssertEqual(host.updates.last, .update(handle: 0, state(a: 1, serving: "teamB", server: 1)))
    }

    func testRapidUpdatesArriveInCallOrder() async {
        let (controller, host) = makeController()
        controller.begin(attributes: attributes, state: state())
        for score in 1...5 { controller.update(state(a: score)) }
        controller.update(state(a: 4))   // an undo
        await controller.waitUntilIdle()
        let scores = host.updates.compactMap { event -> Int? in
            if case .update(_, let s) = event { s.teamAScore } else { nil }
        }
        XCTAssertEqual(scores, [1, 2, 3, 4, 5, 4], "last write wins means the LAST call")
    }

    func testEndEndsTheActivityOnceWithTheGivenPolicyAndLaterUpdatesAreIgnored() async {
        let (controller, host) = makeController()
        controller.begin(attributes: attributes, state: state())
        controller.update(state(a: 11, over: true))
        controller.end(finalState: state(a: 11, over: true), dismissal: .afterDelay(300))
        controller.update(state(a: 12))
        controller.end(finalState: nil, dismissal: .immediate)
        await controller.waitUntilIdle()
        XCTAssertEqual(host.ends, [.end(handle: 0, state(a: 11, over: true), .afterDelay(300))])
        XCTAssertEqual(host.updates.count, 1, "nothing may update after the end")
    }

    func testStartingANewActivityEndsLeftoversFirst() async {
        let (controller, host) = makeController()
        let stale = host.makeHandle(attributes: attributes)
        host.running = [stale]
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        XCTAssertEqual(host.events.first, .end(handle: stale.id, nil, .immediate))
        XCTAssertEqual(host.requests.count, 1)
        XCTAssertEqual(host.running.count, 1, "never two simultaneous activities")
    }

    func testResumeAttachesToTheMatchingRunningActivityInsteadOfStartingAnother() async {
        let (controller, host) = makeController()
        let existing = host.makeHandle(attributes: attributes)
        host.running = [existing]
        controller.resume(attributes: attributes, state: state(a: 3))
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 0)
        XCTAssertEqual(host.events, [.update(handle: existing.id, state(a: 3))])
        controller.update(state(a: 4))
        await controller.waitUntilIdle()
        XCTAssertEqual(host.updates.last, .update(handle: existing.id, state(a: 4)))
    }

    func testResumeReusesTheMatchingSurvivorAndEndsTheRest() async {
        let (controller, host) = makeController()
        let other = PickleballActivityAttributes(
            teamAName: "X", teamBName: "Y", matchFormatSummary: "Doubles • Best of 1", showsGamesWon: false
        )
        let stranger = host.makeHandle(attributes: other)
        let first = host.makeHandle(attributes: attributes)
        let duplicate = host.makeHandle(attributes: attributes)
        host.running = [stranger, first, duplicate]
        controller.resume(attributes: attributes, state: state(a: 2))
        await controller.waitUntilIdle()
        XCTAssertTrue(host.requests.isEmpty)
        XCTAssertEqual(host.updates, [.update(handle: first.id, state(a: 2))])
        XCTAssertEqual(Set(host.ends), [.end(handle: stranger.id, nil, .immediate), .end(handle: duplicate.id, nil, .immediate)])
        XCTAssertEqual(host.running.map(\.id), [first.id])
    }

    func testResumeReplacesARunningActivityOfADifferentMatch() async {
        let (controller, host) = makeController()
        let other = PickleballActivityAttributes(
            teamAName: "X", teamBName: "Y", matchFormatSummary: "Doubles • Best of 1", showsGamesWon: false
        )
        let leftover = host.makeHandle(attributes: other)
        host.running = [leftover]
        controller.resume(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        XCTAssertEqual(host.ends, [.end(handle: leftover.id, nil, .immediate)])
        XCTAssertEqual(host.requests, [.request(attributes, state())])
    }

    func testResumeStartsANewActivityWhenNoneIsRunning() async {
        let (controller, host) = makeController()
        controller.resume(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        XCTAssertEqual(host.events, [.request(attributes, state())])
    }

    func testEndAllCleansUpStrayActivities() async {
        let (controller, host) = makeController()
        host.running = [host.makeHandle(attributes: attributes), host.makeHandle(attributes: attributes)]
        controller.endAll()
        await controller.waitUntilIdle()
        XCTAssertEqual(host.ends.count, 2)
        XCTAssertTrue(host.running.isEmpty)
    }

    func testDisabledAuthorizationIsASilentNoOp() async {
        let (controller, host) = makeController()
        host.areActivitiesEnabled = false
        controller.begin(attributes: attributes, state: state())
        controller.update(state(a: 1))
        controller.end(finalState: nil, dismissal: .immediate)
        controller.resume(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        XCTAssertTrue(host.events.isEmpty)
    }

    // MARK: - The in-app Live Activity switch

    /// The user's Settings switch as the controller sees it (a closure over
    /// this box stands in for `AppSettings.liveActivityEnabled`).
    private final class SettingSwitch {
        var isOn = true
    }

    private func makeController(switch setting: SettingSwitch) -> (LiveActivityController, RecordingLiveActivityHost) {
        let host = RecordingLiveActivityHost()
        return (LiveActivityController(host: host, isEnabled: { setting.isOn }), host)
    }

    func testSwitchedOffBeginResumeAndUpdateDoNothing() async {
        let setting = SettingSwitch()
        setting.isOn = false
        let (controller, host) = makeController(switch: setting)
        controller.begin(attributes: attributes, state: state())
        controller.update(state(a: 1))
        controller.resume(attributes: attributes, state: state(a: 2))
        controller.retryIfNeeded()
        controller.update(state(a: 3))
        await controller.waitUntilIdle()
        XCTAssertTrue(host.events.isEmpty)
    }

    func testSwitchingOnMidMatchStartsExactlyOneActivityWithTheCurrentState() async {
        let setting = SettingSwitch()
        setting.isOn = false
        let (controller, host) = makeController(switch: setting)
        controller.begin(attributes: attributes, state: state())
        controller.update(state(a: 4, b: 2, serving: "teamB", server: 2))
        setting.isOn = true
        controller.enablementChanged()
        await controller.waitUntilIdle()
        XCTAssertEqual(host.events, [.request(attributes, state(a: 4, b: 2, serving: "teamB", server: 2))])
        // And it is a live activity from then on: later points reach it.
        controller.update(state(a: 5, b: 2, serving: "teamB", server: 2))
        await controller.waitUntilIdle()
        XCTAssertEqual(host.updates.count, 1)
    }

    func testSwitchingOffMidMatchEndsTheActivityImmediatelyAndLaterUpdatesAreSkipped() async {
        let setting = SettingSwitch()
        let (controller, host) = makeController(switch: setting)
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        setting.isOn = false
        controller.enablementChanged()
        controller.update(state(a: 1))
        await controller.waitUntilIdle()
        XCTAssertEqual(host.ends, [.end(handle: 0, nil, .immediate)])
        XCTAssertTrue(host.updates.isEmpty)
        XCTAssertTrue(host.running.isEmpty)
    }

    func testOffOnOffEndsWithNoActivityLeft() async {
        let setting = SettingSwitch()
        let (controller, host) = makeController(switch: setting)
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        // Three quick toggles with nothing awaited in between.
        setting.isOn = false
        controller.enablementChanged()
        setting.isOn = true
        controller.enablementChanged()
        setting.isOn = false
        controller.enablementChanged()
        await controller.waitUntilIdle()
        XCTAssertTrue(host.running.isEmpty)
        XCTAssertEqual(host.requests.count, 1, "the in-between ON never got to start a second activity")
        XCTAssertEqual(host.ends.count, 1)
    }

    func testOnOffOnLeavesExactlyOneActivityRunning() async {
        let setting = SettingSwitch()
        let (controller, host) = makeController(switch: setting)
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        setting.isOn = false
        controller.enablementChanged()
        setting.isOn = true
        controller.enablementChanged()
        await controller.waitUntilIdle()
        XCTAssertEqual(host.running.count, 1)
        XCTAssertEqual(host.requests.count, 2)
    }

    func testSwitchingOnWhileAnActivityIsAlreadyRunningDoesNotDuplicateIt() async {
        let setting = SettingSwitch()
        let (controller, host) = makeController(switch: setting)
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        controller.enablementChanged()   // already on: nothing to do
        controller.enablementChanged()
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 1)
        XCTAssertTrue(host.ends.isEmpty)
    }

    func testSwitchingOnAdoptsAnUntrackedRunningActivityOfTheSameMatch() async {
        let setting = SettingSwitch()
        setting.isOn = false
        let (controller, host) = makeController(switch: setting)
        controller.begin(attributes: attributes, state: state(a: 3))
        let survivor = host.makeHandle(attributes: attributes)
        host.running = [survivor]
        setting.isOn = true
        controller.enablementChanged()
        await controller.waitUntilIdle()
        XCTAssertTrue(host.requests.isEmpty, "never a second activity next to the one that exists")
        XCTAssertEqual(host.updates, [.update(handle: survivor.id, state(a: 3))])
    }

    func testSwitchingOnWithNoMatchRunningStartsNothing() async {
        let setting = SettingSwitch()
        setting.isOn = false
        let (controller, host) = makeController(switch: setting)
        setting.isOn = true
        controller.enablementChanged()
        controller.begin(attributes: attributes, state: state())
        controller.end(finalState: nil, dismissal: .immediate)
        controller.enablementChanged()   // the match is over: do not bring it back
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 1, "only the begin; the match was over for the second toggle")
        XCTAssertEqual(host.running.count, 0)
    }

    func testSwitchedOffNeverRetriesAFailedStart() async {
        let setting = SettingSwitch()
        let (controller, host) = makeController(switch: setting)
        host.failRequests = true
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        setting.isOn = false
        controller.update(state(a: 1))
        controller.retryIfNeeded()
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 1, "the one retry is not spent while the switch is off")
    }

    func testARequestFailureNeverThrowsAndRetriesExactlyOnce() async {
        let (controller, host) = makeController()
        host.failRequests = true
        controller.begin(attributes: attributes, state: state())
        controller.update(state(a: 1))      // the one retry: fails again
        controller.update(state(a: 2))      // no further attempt
        await controller.waitUntilIdle()
        controller.end(finalState: nil, dismissal: .immediate)
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 2)
        XCTAssertTrue(host.updates.isEmpty)
        XCTAssertTrue(host.ends.isEmpty)
    }

    func testTheRetryStartsTheActivityWhenTheSecondRequestSucceeds() async {
        let (controller, host) = makeController()
        host.failRequests = true
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        host.failRequests = false
        controller.update(state(a: 1))
        controller.update(state(a: 2))
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests, [.request(attributes, state()), .request(attributes, state(a: 1))])
        XCTAssertEqual(host.updates, [.update(handle: 0, state(a: 2))])
    }

    func testActivitiesTurnedOnMidMatchStartOnTheNextUpdate() async {
        let (controller, host) = makeController()
        host.areActivitiesEnabled = false
        controller.begin(attributes: attributes, state: state())
        controller.update(state(a: 1))      // still off: not an attempt, no retry used
        await controller.waitUntilIdle()
        XCTAssertTrue(host.events.isEmpty)
        host.areActivitiesEnabled = true
        controller.update(state(a: 2))
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests, [.request(attributes, state(a: 2))])
    }

    func testRetryIfNeededCoversAForegroundWithoutAnUpdate() async {
        let (controller, host) = makeController()
        host.failRequests = true
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        host.failRequests = false
        controller.retryIfNeeded()
        controller.retryIfNeeded()           // the retry is single
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 2)
        XCTAssertEqual(host.running.count, 1)
    }

    func testNeverRequestsAgainAfterTheMatchEnded() async {
        let (controller, host) = makeController()
        host.failRequests = true
        controller.begin(attributes: attributes, state: state())
        controller.end(finalState: nil, dismissal: .immediate)
        host.failRequests = false
        controller.update(state(a: 1))
        controller.retryIfNeeded()
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 1)
    }

    func testASwipeDismissedActivityIsNotRequestedAgain() async {
        let (controller, host) = makeController()
        controller.begin(attributes: attributes, state: state())
        await controller.waitUntilIdle()
        // The user swipes the activity away: the system drops it, the handle stays.
        host.running.removeAll()
        controller.update(state(a: 1))
        controller.retryIfNeeded()
        await controller.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 1)
    }

    func testStaleDateIsThreeHoursAfterEachPush() async {
        let host = RecordingLiveActivityHost()
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let controller = LiveActivityController(host: host, now: { fixed })
        controller.begin(attributes: attributes, state: state())
        controller.update(state(a: 1))
        await controller.waitUntilIdle()
        XCTAssertEqual(host.staleDates, [fixed.addingTimeInterval(3 * 60 * 60), fixed.addingTimeInterval(3 * 60 * 60)])
    }

    func testUITestLaunchArgumentSelectsTheNoOpHost() {
        XCTAssertTrue(MyApp.makeLiveActivityHost(arguments: ["-UITest-ResetState"]) is NoOpLiveActivityHost)
        XCTAssertFalse(MyApp.makeLiveActivityHost(arguments: []) is NoOpLiveActivityHost)
    }
}

// MARK: - Wired into ActiveMatchController

@MainActor
final class ActiveMatchControllerLiveActivityTests: XCTestCase {
    private func make(
        container: ModelContainer? = nil,
        defaults: UserDefaults? = nil,
        host: RecordingLiveActivityHost = RecordingLiveActivityHost()
    ) throws -> (ActiveMatchController, LiveActivityController, RecordingLiveActivityHost, ModelContainer, UserDefaults) {
        let container = try container ?? PersistenceContainer.makeInMemoryContainer()
        let defaults = defaults ?? UserDefaults(suiteName: UUID().uuidString)!
        let live = LiveActivityController(host: host)
        let controller = ActiveMatchController(
            modelContext: ModelContext(container), userDefaults: defaults, liveActivity: live
        )
        return (controller, live, host, container, defaults)
    }

    private func start(_ controller: ActiveMatchController, format: MatchFormat = .bestOfOne) {
        controller.stageMatch(PendingMatchSetup(
            configuration: GameConfiguration(), matchFormat: format,
            teamAName: "Smashers", teamBName: "", teamAPlayerIDs: [], teamBPlayerIDs: []
        ))
        controller.confirmFirstServe(.teamA)
    }

    func testStagingAloneStartsNothingAndConfirmFirstServeStartsExactlyOne() async throws {
        let (controller, live, host, _, _) = try make()
        controller.stageMatch(PendingMatchSetup(
            configuration: GameConfiguration(), matchFormat: .bestOfOne,
            teamAName: "S", teamBName: "N", teamAPlayerIDs: [], teamBPlayerIDs: []
        ))
        await live.waitUntilIdle()
        XCTAssertTrue(host.requests.isEmpty, "no activity during the coin flip")

        controller.confirmFirstServe(.teamB)
        await live.waitUntilIdle()
        XCTAssertEqual(host.requests.count, 1)
        guard case .request(let attributes, let state)? = host.requests.first else { return XCTFail("no request") }
        XCTAssertEqual(attributes.teamAName, "S")
        XCTAssertEqual(state.servingTeamRawValue, "teamB")
    }

    func testBlankTeamNamesUseTheResolvedFallbackLikeTheApp() async throws {
        let (controller, live, host, _, _) = try make()
        start(controller)
        await live.waitUntilIdle()
        guard case .request(let attributes, _)? = host.requests.first else { return XCTFail("no request") }
        XCTAssertEqual(attributes.teamAName, "Smashers")
        XCTAssertEqual(attributes.teamBName, "Team B")
    }

    func testPointsUndoAndCorrectionUpdateAndTimeoutDoesNot() async throws {
        let (controller, live, host, _, _) = try make()
        start(controller)
        controller.recordPoint(for: .teamA)
        controller.undo()
        controller.correctScores(teamA: 5, teamB: 3)
        controller.requestTimeout(for: .teamA)
        await live.waitUntilIdle()
        // 1-0, back to 0-0, corrected to 5-3; the timeout changes nothing shown.
        XCTAssertEqual(host.updates.count, 3)
        guard case .update(_, let last)? = host.updates.last else { return XCTFail("no update") }
        XCTAssertEqual(last.teamAScore, 5)
        XCTAssertEqual(last.teamBScore, 3)
    }

    func testFinishingAFinishedMatchEndsWithAShortDismissalAndTheFinalState() async throws {
        let (controller, live, host, _, _) = try make()
        start(controller)
        playOutGame(controller, winner: .teamA)
        try controller.finishMatch()
        await live.waitUntilIdle()
        XCTAssertEqual(host.ends.count, 1)
        guard case .end(_, let final?, let dismissal)? = host.ends.first else { return XCTFail("no end") }
        XCTAssertTrue(final.isMatchOver)
        XCTAssertEqual(dismissal, .afterDelay(LiveActivityController.finishedDismissalDelay))
    }

    func testCancellingEndsImmediately() async throws {
        let (controller, live, host, _, _) = try make()
        start(controller)
        controller.cancelActiveMatch()
        await live.waitUntilIdle()
        XCTAssertEqual(host.ends.count, 1)
        guard case .end(_, _, let dismissal)? = host.ends.first else { return XCTFail("no end") }
        XCTAssertEqual(dismissal, .immediate)
    }

    func testRelaunchWithARunningActivityAttachesInsteadOfStartingAnother() async throws {
        let (first, firstLive, firstHost, container, defaults) = try make()
        start(first)
        first.recordPoint(for: .teamA)
        await firstLive.waitUntilIdle()
        let surviving = try XCTUnwrap(firstHost.running.first)

        // A relaunch: a new controller over the same store, and the system still
        // shows the old activity.
        let secondHost = RecordingLiveActivityHost()
        secondHost.running = [surviving]
        let (resumed, resumedLive, _, _, _) = try make(container: container, defaults: defaults, host: secondHost)
        await resumedLive.waitUntilIdle()
        XCTAssertNotNil(resumed.match)
        XCTAssertTrue(secondHost.requests.isEmpty)
        // The surviving handle belongs to the first host, so the resume's update
        // lands there: one for the point, one for the re-sync after the relaunch.
        XCTAssertEqual(firstHost.updates.count, 2)
    }

    func testRelaunchWithoutARunningActivityStartsOne() async throws {
        let (first, firstLive, _, container, defaults) = try make()
        start(first)
        await firstLive.waitUntilIdle()
        let (_, resumedLive, secondHost, _, _) = try make(container: container, defaults: defaults)
        await resumedLive.waitUntilIdle()
        XCTAssertEqual(secondHost.requests.count, 1)
    }

    func testLaunchWithNoMatchEndsStrayActivities() async throws {
        let host = RecordingLiveActivityHost()
        let attributes = PickleballActivityAttributes(
            teamAName: "A", teamBName: "B", matchFormatSummary: "x", showsGamesWon: false
        )
        host.running = [host.makeHandle(attributes: attributes)]
        let (_, live, _, _, _) = try make(host: host)
        await live.waitUntilIdle()
        XCTAssertEqual(host.ends.count, 1)
        XCTAssertTrue(host.running.isEmpty)
    }

    func testScoringStillWorksWhenTheActivityCannotStart() async throws {
        let host = RecordingLiveActivityHost()
        host.failRequests = true
        let (controller, live, _, _, _) = try make(host: host)
        start(controller)
        controller.recordPoint(for: .teamA)
        await live.waitUntilIdle()
        XCTAssertEqual(controller.match?.currentGame.state.teamAScore, 1)
    }
}
