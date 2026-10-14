# Chemistry Stats & Game Duration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two small, read-only stat features: "with you / against you" chemistry stats on `PlayerDetailView`, and per-match game duration with closest/longest game labels on `MatchDetailView`.

**Architecture:** A new pure function (`MatchRepository.chemistry`) reuses the existing private `mySide` helper, no schema change. A new additive-optional `GameRecord.completedAt` field is populated by `ActiveMatchController` (never the scoring engine), synced inside its existing `recordPoint`/`undo`/`correctScore` wrappers using the exact same points this codebase already hooks `persistSnapshot()` into.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest/XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-14-chemistry-stats-game-duration-design.md`

## Global Constraints

- No change to `PickleballGame`/`PickleballMatch`'s public API — this feature touches only `ActiveMatchController` (ServerTwo target) and `MatchRepository`/`GameRecord` (PickleballKit), never the scoring engine.
- `GameRecord.completedAt` is declared `Date? = nil` — explicit default, matching the house style already used by `TeamSide.players: [SavedPlayer]? = nil` and `SavedPlayer.photoData: Data? = nil`.
- No backfill of `completedAt` for existing `GameRecord` rows, and no history-wide "longest match ever" aggregate — both out of scope per the spec's Non-goals.
- `xcodebuild test` runs with `-maximum-concurrent-test-simulator-destinations 2` — a higher value caused a 30-minute XCUITest hang in this project before.
- Authoritative test results come from `xcrun xcresulttool get test-results summary --path <xcresult>` piped through `python3` — never from raw log greps.
- PickleballKit's own suite runs via `swift test` from inside the `PickleballKit` directory, independent of the app's `xcodebuild test`.

## Review Focus

- **"Me" viewing their own profile must show neither chemistry row.** `showsChemistry` is `mePlayer != nil && mePlayer?.id != player.id` — an implementer could easily invert or drop the second half of that condition, since on the surface "mePlayer is set" looks like the only thing that matters.
- **Undo across a game boundary, not just a point.** `PickleballMatch.undo()` has an explicit branch that removes a just-completed game (`completedGames.removeLast()`) when the match-deciding point is undone — this is the single highest-risk correctness point in the whole feature, since a plain append-only `gameCompletionDates` array would desync from `completedGames` the moment this path is exercised, silently misattributing timestamps to the wrong game from then on.
- **A Best of 1 match must show neither `closestGameID` nor `longestGameID`.** Both need an explicit `orderedGames.count > 1` guard; it's cheap to forget since a single-game match otherwise "just works" through the rest of the comparison logic and produces a wrong answer instead of an obviously-missing one.
- **Pre-feature history (no `completedAt` ever recorded) must show `closestGameID` but never `longestGameID`.** An earlier draft of the spec itself got this backwards once (documented in the spec's own revision history) — these two labels are independently gated, not both-or-nothing, and that asymmetry is easy to re-break in either direction during implementation.
- **A crash-resumed match that later completes more games.** `gameCompletionDates` must be *pre-sized* with `nil` for however many games existed before the crash, not reset to `[]` — resetting would cause the next `recordPoint` call to wrongly append a fresh `Date()` for a game that actually finished before this session started.

---

### Task 1: `MatchRepository.chemistry(between:and:in:)`

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift` (add the new public function near `personalRecord`/`winStreak`/`recentForm`/`myResult`, which all already live together in this file)
- Test: `PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift` (add new test cases alongside the existing `testPersonalRecord*`/`testMyResult*` cases)

**Interfaces:**
- Consumes: the existing private `mySide(for player: SavedPlayer, in match: MatchRecord) -> TeamSide?` helper in the same file (id-match-first, name-component-fallback) — unchanged, not modified by this task.
- Produces: `public func chemistry(between me: SavedPlayer, and other: SavedPlayer, in matches: [MatchRecord]) -> (asPartner: (wins: Int, losses: Int)?, asOpponent: (wins: Int, losses: Int)?)`, consumed by Task 4.

- [ ] **Step 1: Write the failing tests**

Add to `PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift` (matching the file's existing `makeInMemoryContext()`/rally-scoring-config pattern used by `testPersonalRecordCountsOnlyMatchesIncludingThePlayerOnEitherSide` and neighbors):

```swift
func testChemistryPartnerOnlyHistoryPopulatesAsPartnerAndNilsAsOpponent() throws {
    let context = try makeInMemoryContext()
    let repository = MatchRepository(modelContext: context)
    let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)

    let me = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
    let other = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Katie"))

    // Match 1: partners, win 11-7.
    let match1 = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...7 { match1.recordPoint(for: .teamB) }
    for _ in 1...11 { match1.recordPoint(for: .teamA) }
    _ = try repository.saveCompletedMatch(match1, teamAName: "Delon & Katie", teamBName: "Opponents", startedAt: Date(), teamAPlayers: [me, other])

    // Match 2: partners again, lose this time.
    let match2 = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...11 { match2.recordPoint(for: .teamB) }
    _ = try repository.saveCompletedMatch(match2, teamAName: "Delon & Katie", teamBName: "Opponents", startedAt: Date(), teamAPlayers: [me, other])

    let allMatches = try repository.fetchMatchHistory()
    let result = repository.chemistry(between: me, and: other, in: allMatches)

    XCTAssertEqual(result.asPartner?.wins, 1)
    XCTAssertEqual(result.asPartner?.losses, 1)
    XCTAssertNil(result.asOpponent)
}

func testChemistryOpponentOnlyHistoryPopulatesAsOpponentAndNilsAsPartner() throws {
    let context = try makeInMemoryContext()
    let repository = MatchRepository(modelContext: context)
    let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)

    let me = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
    let other = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Katie"))

    // Opponents, me (team A) wins.
    let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...7 { match.recordPoint(for: .teamB) }
    for _ in 1...11 { match.recordPoint(for: .teamA) }
    _ = try repository.saveCompletedMatch(match, teamAName: "Delon", teamBName: "Katie", startedAt: Date(), teamAPlayers: [me], teamBPlayers: [other])

    let allMatches = try repository.fetchMatchHistory()
    let result = repository.chemistry(between: me, and: other, in: allMatches)

    XCTAssertNil(result.asPartner)
    XCTAssertEqual(result.asOpponent?.wins, 1)
    XCTAssertEqual(result.asOpponent?.losses, 0)
}

func testChemistryMixedHistorySplitsCorrectlyBetweenBothRelationships() throws {
    let context = try makeInMemoryContext()
    let repository = MatchRepository(modelContext: context)
    let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)

    let me = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
    let other = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Katie"))

    // Partnered once, won.
    let partnered = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...11 { partnered.recordPoint(for: .teamA) }
    _ = try repository.saveCompletedMatch(partnered, teamAName: "Delon & Katie", teamBName: "Opponents", startedAt: Date(), teamAPlayers: [me, other])

    // Opposed once, lost.
    let opposed = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...11 { opposed.recordPoint(for: .teamB) }
    _ = try repository.saveCompletedMatch(opposed, teamAName: "Delon", teamBName: "Katie", startedAt: Date(), teamAPlayers: [me], teamBPlayers: [other])

    let allMatches = try repository.fetchMatchHistory()
    let result = repository.chemistry(between: me, and: other, in: allMatches)

    XCTAssertEqual(result.asPartner?.wins, 1)
    XCTAssertEqual(result.asPartner?.losses, 0)
    XCTAssertEqual(result.asOpponent?.wins, 0)
    XCTAssertEqual(result.asOpponent?.losses, 1)
}

func testChemistryNoSharedMatchesReturnsBothNil() throws {
    let context = try makeInMemoryContext()
    let repository = MatchRepository(modelContext: context)
    let me = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
    let other = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Katie"))

    let result = repository.chemistry(between: me, and: other, in: [])

    XCTAssertNil(result.asPartner)
    XCTAssertNil(result.asOpponent)
}

func testChemistryGuardsAgainstSamePlayerPassedTwice() throws {
    let context = try makeInMemoryContext()
    let repository = MatchRepository(modelContext: context)
    let me = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
    let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)

    let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...11 { match.recordPoint(for: .teamA) }
    _ = try repository.saveCompletedMatch(match, teamAName: "Delon", teamBName: "Opponent", startedAt: Date(), teamAPlayers: [me])

    let allMatches = try repository.fetchMatchHistory()
    let result = repository.chemistry(between: me, and: me, in: allMatches)

    XCTAssertNil(result.asPartner)
    XCTAssertNil(result.asOpponent)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter SavedPlayerRepositoryTests`
Expected: FAIL — `chemistry(between:and:in:)` doesn't exist yet.

- [ ] **Step 3: Implement `chemistry`**

Add to `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`, placed directly after the existing `myResult(for:in:)` function (same file, same section as the other personal-stats functions):

```swift
/// `me`'s record against `other`, split by relationship. Each side is
/// `nil` if `me` and `other` never shared that relationship (e.g. two
/// players who have only ever partnered have a `nil` asOpponent, not a
/// 0-0 one) — a relationship that never happened isn't a stat, it's
/// nothing to report.
public func chemistry(
    between me: SavedPlayer,
    and other: SavedPlayer,
    in matches: [MatchRecord]
) -> (asPartner: (wins: Int, losses: Int)?, asOpponent: (wins: Int, losses: Int)?) {
    // A caller passing the same player for both arguments isn't a real
    // relationship — without this guard every one of their matches would
    // count as a win/loss "with/against themselves."
    guard me.id != other.id else { return (nil, nil) }

    var partnerWins = 0, partnerLosses = 0
    var opponentWins = 0, opponentLosses = 0
    var hasPartnerMatch = false, hasOpponentMatch = false

    for match in matches {
        guard let mySide = mySide(for: me, in: match),
              let otherSide = mySide(for: other, in: match) else { continue }

        let won = mySide.team == match.winningTeam
        if mySide.team == otherSide.team {
            hasPartnerMatch = true
            won ? (partnerWins += 1) : (partnerLosses += 1)
        } else {
            hasOpponentMatch = true
            won ? (opponentWins += 1) : (opponentLosses += 1)
        }
    }

    return (
        hasPartnerMatch ? (partnerWins, partnerLosses) : nil,
        hasOpponentMatch ? (opponentWins, opponentLosses) : nil
    )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test --filter SavedPlayerRepositoryTests`
Expected: PASS, all 5 new cases plus every pre-existing case in the file.

- [ ] **Step 5: Run the full PickleballKit suite**

Run: `cd "PickleballKit" && swift test`
Expected: PASS, 100% — confirms this addition didn't disturb anything else in the package.

- [ ] **Step 6: Commit**

```bash
git add PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift
git commit -m "Add MatchRepository.chemistry(between:and:in:) for With You/Against You stats"
```

---

### Task 2: `GameRecord.completedAt` field + `saveCompletedMatch` parameter

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/GameRecord.swift`
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift` (the `saveCompletedMatch` function, lines ~65-144)
- Test: `PickleballKit/Tests/PickleballKitTests/MatchRepositoryHistoryTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `GameRecord.completedAt: Date?`, and `saveCompletedMatch(..., gameCompletionDates: [Date?] = [])` — both consumed by Task 3 (which supplies real values) and Task 5 (which reads `completedAt` for the closest/longest computation).

- [ ] **Step 1: Write the failing tests**

Add to `PickleballKit/Tests/PickleballKitTests/MatchRepositoryHistoryTests.swift`, after the existing `testSaveCompletedMatchPersistsFullGraph`:

```swift
func testSaveCompletedMatchAppliesGameCompletionDatesByPosition() throws {
    let context = try makeInMemoryContext()
    let repository = MatchRepository(modelContext: context)
    let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)

    let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...11 { match.recordPoint(for: .teamA) }
    for _ in 1...11 { match.recordPoint(for: .teamA) }

    let firstGameEnd = Date(timeIntervalSince1970: 1000)
    let secondGameEnd = Date(timeIntervalSince1970: 2000)

    let saved = try repository.saveCompletedMatch(
        match,
        teamAName: "A",
        teamBName: "B",
        startedAt: Date(timeIntervalSince1970: 0),
        gameCompletionDates: [firstGameEnd, secondGameEnd]
    )

    let games = try XCTUnwrap(saved.games).sorted { $0.gameNumber < $1.gameNumber }
    XCTAssertEqual(games.count, 2)
    XCTAssertEqual(games[0].completedAt, firstGameEnd)
    XCTAssertEqual(games[1].completedAt, secondGameEnd)
}

func testSaveCompletedMatchOmittingGameCompletionDatesLeavesEveryGameNil() throws {
    let context = try makeInMemoryContext()
    let repository = MatchRepository(modelContext: context)
    let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

    let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...11 { match.recordPoint(for: .teamA) }

    // No gameCompletionDates argument at all — every existing caller in
    // this file (and in the app) must keep compiling unchanged.
    let saved = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())

    let game = try XCTUnwrap(saved.games?.first)
    XCTAssertNil(game.completedAt)
}

func testSaveCompletedMatchToleratesShorterGameCompletionDatesThanGames() throws {
    let context = try makeInMemoryContext()
    let repository = MatchRepository(modelContext: context)
    let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven, winByTwo: true)

    let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
    for _ in 1...11 { match.recordPoint(for: .teamA) }
    for _ in 1...11 { match.recordPoint(for: .teamA) }

    // Only one date for two games — simulates a crash-resumed match whose
    // earlier game predates this session's own timestamp capture. Must
    // degrade to nil for the uncovered game, not crash.
    let onlyDate = Date(timeIntervalSince1970: 500)
    let saved = try repository.saveCompletedMatch(
        match,
        teamAName: "A",
        teamBName: "B",
        startedAt: Date(timeIntervalSince1970: 0),
        gameCompletionDates: [onlyDate]
    )

    let games = try XCTUnwrap(saved.games).sorted { $0.gameNumber < $1.gameNumber }
    XCTAssertEqual(games[0].completedAt, onlyDate)
    XCTAssertNil(games[1].completedAt)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter MatchRepositoryHistoryTests`
Expected: FAIL — `GameRecord` has no `completedAt` member, and `saveCompletedMatch` has no `gameCompletionDates` parameter.

- [ ] **Step 3: Add the field to `GameRecord`**

In `PickleballKit/Sources/PickleballKit/Persistence/GameRecord.swift`, add alongside the other stored properties (after `winningTeamRawValue`, before `match`):

```swift
    /// When this specific game finished, captured live by
    /// `ActiveMatchController` (never by the scoring engine — see
    /// `MatchRepository.saveCompletedMatch`'s doc comment). `nil` for any
    /// match saved before this field existed, and for a game that
    /// completed before a crash/relaunch this session resumed from.
    public var completedAt: Date? = nil
```

- [ ] **Step 4: Thread `gameCompletionDates` through `saveCompletedMatch`**

In `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`, modify the function signature (around line 66-74):

```swift
    @discardableResult
    public func saveCompletedMatch(
        _ match: PickleballMatch,
        teamAName: String,
        teamBName: String,
        startedAt: Date,
        completedAt: Date = Date(),
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = [],
        gameCompletionDates: [Date?] = []
    ) throws -> MatchRecord {
```

Inside the existing `for game in match.completedGames` loop (around line 107-131), set `completedAt` on each constructed `GameRecord` using a bounds-safe lookup. No `Array` safe-subscript extension exists anywhere in PickleballKit yet (verified: `grep -rn "subscript(safe" PickleballKit/Sources PickleballKit/Tests` returns nothing) — add this one, near the top of `MatchRepository.swift`, outside the class:

```swift
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

Then, immediately after `gameRecord.match = record` inside the loop:

```swift
            gameRecord.completedAt = gameCompletionDates[safe: gameNumber - 1] ?? nil
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test --filter MatchRepositoryHistoryTests`
Expected: PASS, all 3 new cases plus every pre-existing case in the file.

- [ ] **Step 6: Run the full PickleballKit suite**

Run: `cd "PickleballKit" && swift test`
Expected: PASS, 100%.

- [ ] **Step 7: Commit**

```bash
git add PickleballKit/Sources/PickleballKit/Persistence/GameRecord.swift PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift PickleballKit/Tests/PickleballKitTests/MatchRepositoryHistoryTests.swift
git commit -m "Add GameRecord.completedAt and thread gameCompletionDates through saveCompletedMatch"
```

---

### Task 3: `ActiveMatchController` tracks `gameCompletionDates` live

**Files:**
- Modify: `ServerTwo/ActiveMatchController.swift`
- Test: `ServerTwoTests/ActiveMatchControllerTests.swift`

**Interfaces:**
- Consumes: `GameRecord.completedAt` and `saveCompletedMatch(..., gameCompletionDates:)` from Task 2.
- Produces: `ActiveMatchController.gameCompletionDates: [Date?]` (new `private(set)` property), threaded into `finishMatch()`'s existing `saveCompletedMatch` call — not consumed by any later task directly, but this is the only place real timestamps ever originate, so Task 5's `longestGameID` has no real data to show without it.

- [ ] **Step 1: Write the failing tests**

Add to `ServerTwoTests/ActiveMatchControllerTests.swift`, reusing the file's existing `makeController()`/`start()` helpers:

```swift
func testGameCompletionDatesStaysCorrectlySizedAcrossUndoAndReplay() throws {
    let (controller, _) = try makeController()
    start(controller, matchFormat: .bestOfThree, teamAName: "A", teamBName: "B")

    // Win game 1 outright (11-0).
    for _ in 1...11 { controller.recordPoint(for: .teamA) }
    XCTAssertEqual(controller.gameCompletionDates.count, 1)

    // Undo the game-winning point — this reverts completedGames back to
    // empty, which must shrink gameCompletionDates back to empty too, not
    // leave a stale premature timestamp sitting at index 0.
    controller.undo()
    XCTAssertEqual(controller.gameCompletionDates.count, 0)

    // Replay the real winning point for game 1.
    controller.recordPoint(for: .teamA)
    XCTAssertEqual(controller.gameCompletionDates.count, 1)

    // Win game 2 as well — now two completed games, two dates, and the
    // two dates must be distinct (not the same stale value reused).
    for _ in 1...11 { controller.recordPoint(for: .teamA) }
    XCTAssertEqual(controller.gameCompletionDates.count, 2)
    XCTAssertNotEqual(controller.gameCompletionDates[0], controller.gameCompletionDates[1])
}

func testGameCompletionDatesResetsToEmptyOnFreshMatch() throws {
    let (controller, _) = try makeController()
    start(controller, teamAName: "A", teamBName: "B")
    for _ in 1...11 { controller.recordPoint(for: .teamA) }
    XCTAssertEqual(controller.gameCompletionDates.count, 1)

    _ = try controller.finishMatch()

    // A brand new match must not inherit the previous match's dates.
    start(controller, teamAName: "C", teamBName: "D")
    XCTAssertEqual(controller.gameCompletionDates.count, 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from the project root):
```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -only-testing:ServerTwoTests/ActiveMatchControllerTests -resultBundlePath /tmp/task3-red.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task3-red.xcresult
```
Expected: FAIL — `gameCompletionDates` doesn't exist on `ActiveMatchController` yet.

- [ ] **Step 3: Implement the tracking**

In `ServerTwo/ActiveMatchController.swift`, add a new stored property near `lastCanceledSetup` (around line 81):

```swift
    /// Positional with `match?.completedGames` — index `i` is when game
    /// `i`'s winning point was recorded. `nil` entries are games that
    /// completed before this session's own timestamp capture began (a
    /// crash-resumed match's pre-crash games — see `resumeIfNeeded`
    /// below), never a placeholder for "forgot to record." Never
    /// persisted to `GameRecord`/`MatchRecord` directly — `finishMatch()`
    /// hands the whole array to `saveCompletedMatch`, which is the only
    /// place it's written to disk.
    private(set) var gameCompletionDates: [Date?] = []
```

Add a private sync helper near `persistSnapshot()` (around line 274):

```swift
    /// Called from `recordPoint`/`undo`/`correctScore` only — each of
    /// those can move `completedGames.count` by exactly one in either
    /// direction, so a plain grow-by-one/shrink-by-one here is correct;
    /// it would NOT be correct if called from anywhere that could skip
    /// multiple games at once.
    private func syncGameCompletionDates() {
        guard let count = match?.completedGames.count else { return }
        if gameCompletionDates.count > count {
            gameCompletionDates.removeLast(gameCompletionDates.count - count)
        } else if gameCompletionDates.count < count {
            gameCompletionDates.append(contentsOf: Array(repeating: Date(), count: count - gameCompletionDates.count))
        }
    }
```

Call it from the three wrapper methods (around lines 180-193):

```swift
    func recordPoint(for team: Team) {
        match?.recordPoint(for: team)
        syncGameCompletionDates()
        persistSnapshot()
    }

    func undo() {
        match?.undo()
        syncGameCompletionDates()
        persistSnapshot()
    }

    func correctScore(team: Team, to newScore: Int) {
        match?.correctScore(team: team, to: newScore)
        syncGameCompletionDates()
        persistSnapshot()
    }
```

Reset to empty in `confirmFirstServe` (around line 157-178), right before the existing `persistSnapshot()` call at the end of the method:

```swift
        gameCompletionDates = []
        persistSnapshot()
```

Pre-size (not reset) in `resumeIfNeeded` (around line 118-135), right after the `lifecycleState = .active(...)` assignment:

```swift
        gameCompletionDates = Array(repeating: nil, count: resumed.match.completedGames.count)
```

Thread it into `finishMatch()`'s existing `saveCompletedMatch` call (around line 216-223):

```swift
        let record = try repository.saveCompletedMatch(
            info.match,
            teamAName: info.teamAName,
            teamBName: info.teamBName,
            startedAt: info.startedAt,
            teamAPlayers: teamAPlayers,
            teamBPlayers: teamBPlayers,
            gameCompletionDates: gameCompletionDates
        )
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -only-testing:ServerTwoTests/ActiveMatchControllerTests -resultBundlePath /tmp/task3-green.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task3-green.xcresult
```
Expected: PASS, the 2 new cases plus every pre-existing case in `ActiveMatchControllerTests`.

- [ ] **Step 5: Commit**

```bash
git add ServerTwo/ActiveMatchController.swift ServerTwoTests/ActiveMatchControllerTests.swift
git commit -m "Track per-game completion dates in ActiveMatchController, undo-safe"
```

---

### Task 4: `PlayerDetailView` chemistry rows

**Files:**
- Modify: `ServerTwo/Players/PlayerDetailView.swift`
- Test: `ServerTwoUITests/` (new scratch-style test, or a permanent addition — see Step 1; follow this project's established convention of a temporary scratch UI test for visual verification, promoted to permanent only if the plan's reviewer asks for it)

**Interfaces:**
- Consumes: `MatchRepository.chemistry(between:and:in:)` from Task 1, and the already-existing `MatchRepository.fetchMePlayer()` (no changes needed to that function).
- Produces: nothing consumed by a later task — this is a leaf UI task.

- [ ] **Step 1: Write the failing UI test**

Create `ServerTwoUITests/ScratchChemistryRowsCheck.swift` (temporary, matching this project's established pattern — deleted at the end of this task once confirmed, per Step 6 below; this project's Xcode target uses file-system-synchronized groups, so no `project.pbxproj` edit is needed for this file to be picked up):

```swift
import XCTest

final class ScratchChemistryRowsCheck: XCTestCase {
    func testChemistryRowsAppearForOtherPlayerWhenMeIsSetAndOmittedOnOwnProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        playSinglesMatch(app, teamA: "Delon", teamB: "Katie")

        // Set "Delon" as Me via Manage Players.
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()
        app.buttons["SetMe.Delon"].tap()

        // Viewing Katie's profile (not Me) — chemistry rows should appear.
        app.staticTexts["PlayerRow.Katie"].tap()
        XCTAssertTrue(app.staticTexts["As Your Opponent"].waitForExistence(timeout: 3))

        app.navigationBars.buttons.firstMatch.tap()

        // Viewing Delon's own profile (Me) — chemistry rows must NOT appear.
        app.staticTexts["PlayerRow.Delon"].tap()
        XCTAssertTrue(app.navigationBars["Delon"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["As Your Opponent"].exists)
        XCTAssertFalse(app.staticTexts["As Your Partner"].exists)
    }

    private func playSinglesMatch(_ app: XCUIApplication, teamA: String, teamB: String) {
        app.tabBars.buttons["Play"].tap()
        let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamAField, in: app)
        app.swipeUp()
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }

        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText(teamA)

        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText(teamB)

        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()

        let flipCoinButton = app.buttons["Flip Coin"]
        XCTAssertTrue(flipCoinButton.waitForExistence(timeout: 2))
        flipCoinButton.tap()
        let beginMatchButton = app.buttons["Begin Match"]
        XCTAssertTrue(beginMatchButton.waitForExistence(timeout: 2))
        beginMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -only-testing:ServerTwoUITests/ScratchChemistryRowsCheck -resultBundlePath /tmp/task4-red.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task4-red.xcresult
```
Expected: FAIL — no "As Your Opponent"/"As Your Partner" text exists anywhere yet.

- [ ] **Step 3: Add `mePlayer` fetch and the chemistry rows**

In `ServerTwo/Players/PlayerDetailView.swift`, add a new `@State` property alongside the existing ones (line 16):

```swift
    @State private var mePlayer: SavedPlayer?
```

Add a computed property near `statDivider` (around line 132):

```swift
    private var showsChemistry: Bool {
        mePlayer != nil && mePlayer?.id != player.id
    }
```

In `loadRecord()` (around line 192-203), fetch `mePlayer` and compute chemistry, storing it in a new `@State` alongside `record`:

```swift
    @State private var chemistry: (asPartner: (wins: Int, losses: Int)?, asOpponent: (wins: Int, losses: Int)?)?
```

```swift
    private func loadRecord() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            let allMatches = try repository.fetchMatchHistory()
            record = repository.personalRecord(for: player, in: allMatches)
            recentForm = repository.recentForm(for: player, in: allMatches)
            matches = allMatches.filter { repository.myResult(for: player, in: $0) != nil }
            mePlayer = try repository.fetchMePlayer()
            if let mePlayer, mePlayer.id != player.id {
                chemistry = repository.chemistry(between: mePlayer, and: player, in: allMatches)
            } else {
                chemistry = nil
            }
            loadError = nil
        } catch {
            loadError = error
        }
    }
```

Add the two rows inside the existing `if let record { ... }` block (around line 71, right after the Recent Form `Divider()`/`HStack` block, before its closing brace):

```swift
                    if showsChemistry, let chemistry {
                        if let asPartner = chemistry.asPartner {
                            Divider()
                            HStack {
                                Text("As Your Partner")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(asPartner.wins) - \(asPartner.losses)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            .padding(.vertical, 4)
                        }
                        if let asOpponent = chemistry.asOpponent {
                            Divider()
                            HStack {
                                Text("As Your Opponent")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(asOpponent.wins) - \(asOpponent.losses)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            .padding(.vertical, 4)
                        }
                    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -only-testing:ServerTwoUITests/ScratchChemistryRowsCheck -resultBundlePath /tmp/task4-green.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task4-green.xcresult
```
Expected: PASS.

- [ ] **Step 5: Visually verify with a screenshot**

Add a screenshot capture to the test (write to `/Users/delonsampaio/Downloads/chemistry-rows.png`, following this project's established scratch-test screenshot pattern) at the point where Katie's profile is showing the chemistry rows, re-run, and view the image to confirm the rows read correctly (not just that the accessibility text exists).

- [ ] **Step 6: Delete the scratch test**

```bash
rm ServerTwoUITests/ScratchChemistryRowsCheck.swift
```

- [ ] **Step 7: Run the full test suite to confirm nothing else broke**

```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -resultBundlePath /tmp/task4-full.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task4-full.xcresult
```
Expected: PASS, every test in both `ServerTwoTests` and `ServerTwoUITests`.

- [ ] **Step 8: Commit**

```bash
git add ServerTwo/Players/PlayerDetailView.swift
git commit -m "Show With You/Against You chemistry rows on PlayerDetailView"
```

---

### Task 5: `MatchDetailView` duration, closest/longest game labels

**Files:**
- Modify: `ServerTwo/History/MatchDetailView.swift`
- Test: `ServerTwoTests/MatchDetailViewTests.swift` (new file — precise unit coverage of the closest/longest logic, which is far more reliable here than driving exact score margins through simulated taps)
- Test: `ServerTwoUITests/` (scratch test, same pattern as Task 4 — visual/end-to-end confirmation only)

**Interfaces:**
- Consumes: `GameRecord.completedAt` from Task 2 (for `longestGameID`) and real data from Task 3 (a freshly-played match actually has non-nil `completedAt` values to show "Longest Game" with) — `closestGameID` needs only `teamAFinalScore`/`teamBFinalScore`, already present regardless of either other task.
- Produces: nothing consumed by a later task — this is the final leaf task.

**A note on visibility:** `closestGameID` and `longestGameID` are declared without `private` (plain `internal`, this file's default) specifically so `ServerTwoTests/MatchDetailViewTests.swift` can construct a `MatchDetailView` directly and assert on them via `@testable import ServerTwo` — the same pattern `ActiveMatchControllerTests`/`RematchRequestTests` already use for testing logic that isn't itself exposed as a public API. Exercising exact score margins and ties by simulating dozens of precise UI taps (as an earlier draft of this task's UI test did) is both slower and far more fragile than asserting directly on the computed property.

- [ ] **Step 1: Write the failing unit tests**

Create `ServerTwoTests/MatchDetailViewTests.swift`:

```swift
import XCTest
import SwiftData
@testable import ServerTwo
import PickleballKit

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
            // Loser's points first, so the winner's final point is also
            // the game-deciding one (see SavedPlayerRepositoryTests for
            // the same established pattern).
            if teamAScore > teamBScore {
                for _ in 0..<teamBScore { match.recordPoint(for: .teamB) }
                for _ in 0..<teamAScore { match.recordPoint(for: .teamA) }
            } else {
                for _ in 0..<teamAScore { match.recordPoint(for: .teamA) }
                for _ in 0..<teamBScore { match.recordPoint(for: .teamB) }
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
}
```

- [ ] **Step 2: Run the unit tests to verify they fail**

```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -only-testing:ServerTwoTests/MatchDetailViewTests -resultBundlePath /tmp/task5-red.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task5-red.xcresult
```
Expected: FAIL — `closestGameID`/`longestGameID` don't exist on `MatchDetailView` yet.

- [ ] **Step 3: Add the computed properties**

In `ServerTwo/History/MatchDetailView.swift`, add two new computed properties after `orderedGames` (around line 17) — note no `private` keyword, per the visibility note above:

```swift
    var durationText: String? {
        let interval = match.completedAt.timeIntervalSince(match.startedAt)
        guard interval >= 0 else { return nil }
        guard interval >= 60 else { return "< 1 min" }
        return Duration.seconds(interval)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var closestGameID: GameRecord.ID? {
        guard orderedGames.count > 1 else { return nil }
        let margins = Set(orderedGames.map { abs($0.teamAFinalScore - $0.teamBFinalScore) })
        guard margins.count > 1 else { return nil }

        return orderedGames.min { lhs, rhs in
            let lhsMargin = abs(lhs.teamAFinalScore - lhs.teamBFinalScore)
            let rhsMargin = abs(rhs.teamAFinalScore - rhs.teamBFinalScore)
            if lhsMargin != rhsMargin { return lhsMargin < rhsMargin }
            let lhsTotal = lhs.teamAFinalScore + lhs.teamBFinalScore
            let rhsTotal = rhs.teamAFinalScore + rhs.teamBFinalScore
            return lhsTotal > rhsTotal
        }?.id
    }

    var longestGameID: GameRecord.ID? {
        guard orderedGames.count > 1 else { return nil }
        guard orderedGames.allSatisfy({ $0.completedAt != nil }) else { return nil }

        var previousCheckpoint = match.startedAt
        var longest: (id: GameRecord.ID, duration: TimeInterval)?
        for game in orderedGames {
            let completedAt = game.completedAt!
            let duration = completedAt.timeIntervalSince(previousCheckpoint)
            if longest == nil || duration > longest!.duration {
                longest = (game.id, duration)
            }
            previousCheckpoint = completedAt
        }
        return longest?.id
    }
```

- [ ] **Step 4: Run the unit tests to verify they pass**

```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -only-testing:ServerTwoTests/MatchDetailViewTests -resultBundlePath /tmp/task5-green.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task5-green.xcresult
```
Expected: PASS, all 6 cases.

- [ ] **Step 5: Show the duration in `resultCard`**

In `resultCard` (around line 76-107), add the duration next to the existing `formatSummary` pill:

```swift
                if let formatSummary {
                    Text(formatSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let durationText {
                    Text(durationText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
```

- [ ] **Step 6: Show the tags in `gameCard`**

In `gameCard(_:)` (around line 109-160), add the tags right after the `Text("Game \(game.gameNumber)")` line:

```swift
            HStack(spacing: 6) {
                Text("Game \(game.gameNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if game.id == closestGameID {
                    Text("Closest Game")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }
                if game.id == longestGameID {
                    Text("Longest Game")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue, in: Capsule())
                }
            }
```

(Replacing the existing standalone `Text("Game \(game.gameNumber)")` line with this `HStack`.)

- [ ] **Step 7: Write a UI test for visual/end-to-end confirmation**

The precise logic (ties, margins, pre-feature history, crash-resume) is already covered by Step 1's unit tests. This UI test only confirms the feature actually renders in a real, live-played match — it doesn't need to control exact score margins. Create `ServerTwoUITests/ScratchDurationClosestLongestCheck.swift`:

```swift
import XCTest

final class ScratchDurationClosestLongestCheck: XCTestCase {
    func testBestOfThreeMatchShowsDurationAndAtLeastOneTag() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        playBestOfThreeMatch(app, teamA: "Delon", teamB: "Katie")

        app.tabBars.buttons["History"].tap()
        let row = app.staticTexts["Delon vs Katie"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()

        XCTAssertTrue(app.navigationBars["Match Detail"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'min'")).firstMatch.waitForExistence(timeout: 3))
        // closestGameID is guaranteed to be non-nil for any Best of 3 where
        // the games aren't all identically scored — real live play with
        // distinct final scores per game satisfies that easily.
        XCTAssertTrue(app.staticTexts["Closest Game"].waitForExistence(timeout: 2))
    }

    func testBestOfOneMatchShowsNeitherClosestNorLongestTag() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        playSinglesMatch(app, teamA: "Delon", teamB: "Katie")

        app.tabBars.buttons["History"].tap()
        let row = app.staticTexts["Delon vs Katie"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()

        XCTAssertTrue(app.navigationBars["Match Detail"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Closest Game"].exists)
        XCTAssertFalse(app.staticTexts["Longest Game"].exists)
    }

    private func playSinglesMatch(_ app: XCUIApplication, teamA: String, teamB: String) {
        app.tabBars.buttons["Play"].tap()
        let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamAField, in: app)
        app.swipeUp()
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }

        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText(teamA)

        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText(teamB)

        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()

        let flipCoinButton = app.buttons["Flip Coin"]
        XCTAssertTrue(flipCoinButton.waitForExistence(timeout: 2))
        flipCoinButton.tap()
        let beginMatchButton = app.buttons["Begin Match"]
        XCTAssertTrue(beginMatchButton.waitForExistence(timeout: 2))
        beginMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()
    }

    private func playBestOfThreeMatch(_ app: XCUIApplication, teamA: String, teamB: String) {
        app.tabBars.buttons["Play"].tap()
        let teamAField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamAField, in: app)
        app.swipeUp()
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }
        let bestOfThreeToggle = app.buttons["Best of 3"]
        if bestOfThreeToggle.exists { bestOfThreeToggle.tap() }

        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText(teamA)

        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText(teamB)

        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()

        let flipCoinButton = app.buttons["Flip Coin"]
        XCTAssertTrue(flipCoinButton.waitForExistence(timeout: 2))
        flipCoinButton.tap()
        let beginMatchButton = app.buttons["Begin Match"]
        XCTAssertTrue(beginMatchButton.waitForExistence(timeout: 2))
        beginMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        let teamBZone = app.buttons["scoreZone.teamB"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]

        // Game 1: Team A wins 11-0.
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        // Game 2: Team B wins 11-9 (distinct margin from game 1 and 3, so
        // closestGameID is guaranteed non-nil regardless of exact taps).
        for _ in 0..<9 {
            if finishButton.exists { break }
            teamBZone.tap()
            if finishButton.exists { break }
            teamAZone.tap()
        }
        for _ in 0..<2 {
            if finishButton.exists { break }
            teamBZone.tap()
        }
        // Game 3 (deciding): Team A wins.
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()
    }
}
```

- [ ] **Step 8: Run the UI test to verify it passes**

```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -only-testing:ServerTwoUITests/ScratchDurationClosestLongestCheck -resultBundlePath /tmp/task5-ui-green.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task5-ui-green.xcresult
```
Expected: PASS, both cases.

- [ ] **Step 9: Visually verify with a screenshot**

Add a screenshot capture at the point the Best of 3 match's detail view is showing, re-run, and view the image to confirm the duration pill and tags read correctly and don't crowd the existing layout.

- [ ] **Step 10: Delete the scratch test**

```bash
rm ServerTwoUITests/ScratchDurationClosestLongestCheck.swift
```

- [ ] **Step 11: Run the full test suite one final time**

```bash
xcodebuild test -project ServerTwo.xcodeproj -scheme ServerTwo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -maximum-concurrent-test-simulator-destinations 2 -resultBundlePath /tmp/task5-full.xcresult
xcrun xcresulttool get test-results summary --path /tmp/task5-full.xcresult
cd "PickleballKit" && swift test
```
Expected: PASS, every test in `ServerTwoTests`, `ServerTwoUITests`, and the PickleballKit package.

- [ ] **Step 12: Commit**

```bash
git add ServerTwo/History/MatchDetailView.swift ServerTwoTests/MatchDetailViewTests.swift
git commit -m "Show match duration and closest/longest game tags on MatchDetailView"
```
