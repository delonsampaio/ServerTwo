# PickleballKit Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SwiftData persistence to `PickleballKit`: a relational,
CloudKit-synced schema for completed match history, a local-only
crash-recovery snapshot for in-progress matches, a rehydration API on the
engine itself, and a `MatchRepository` wrapping all SwiftData access.

**Architecture:** Completed-match history (`TeamSide`/`MatchRecord`/
`GameRecord`/`PointEvent`) is a normal relational SwiftData schema, synced
via CloudKit, because that data is genuinely browsed and queried later.
In-progress crash recovery (`InProgressGameState`) is a single row holding
one Codable-encoded JSON blob of the whole live match, local-only and
excluded from CloudKit, because it's read back exactly once as a whole.
`PickleballGame`/`PickleballMatch` each gain a second ("resuming")
initializer so a saved match can be fully reconstructed with its undo
stack intact. `MatchRepository` is the only code path that touches
`ModelContext`.

**Tech Stack:** Swift 6.4, SwiftData (macOS 14+/iOS 17+, already the
package's platform floor), XCTest, the existing `PickleballKit` local
Swift Package.

**Spec:** `docs/superpowers/specs/2026-10-06-server-two-design.md`
(Section 3.3 Persistence, Section 3.4 Sync & communication)

## Global Constraints

- CloudKit container identifier: `iCloud.com.delonsampaio.ServerTwo`
  (already configured in the Xcode project's entitlements).
- `InProgressGameState` is local-only and must never appear in a
  CloudKit-synced `ModelConfiguration` — Spec §3.3.
- Only **completed** matches sync via CloudKit; an in-progress game never
  leaves the device mid-play — Spec §3.4, confirmed in Phase 1's final
  review (this is what keeps the demo-cap gate and undo correctness
  intact across devices).
- Every object reachable from a SwiftData relationship must be explicitly
  passed to `modelContext.insert(...)` — do not rely on cascade-insert
  through relationships alone. Verified during plan authoring: relying on
  cascade-insert for a larger nested graph (11 `PointEvent` rows under one
  `GameRecord`) nondeterministically produced an incomplete object count.
  Explicit insertion of every object eliminated it.
- SwiftData to-many relationship arrays (`@Relationship` properties) have
  **no guaranteed order**. Any code that needs order (e.g. a point-by-point
  log) must sort explicitly — see `GameRecord.orderedPoints`. Verified
  during plan authoring: this was the root cause of an apparently-flaky
  test where `points.count` was always correct but `points.last` returned
  an arbitrary element.
- All stored properties on CloudKit-synced `@Model` types must be optional
  or have a default value, and to-many relationships must be optional
  arrays with an explicit `inverse:` — CloudKit's schema requirements.
- `PickleballKit` still has zero UI imports (`import SwiftData` and
  `import Foundation` are the only new imports this phase introduces).

## Review Focus

- A point-by-point log built from `GameRecord.points` directly (not
  `orderedPoints`) will compile, run, and look correct in a quick manual
  check, but silently show points in the wrong order — SwiftData relationship
  arrays are unordered and this is exactly the kind of bug that only
  shows up after enough rows accumulate to make the unordered-ness visible.
  Covered in Task 6 (`orderedPoints`) and Task 9 (uses it).
- `derivePointEvents` must only count transitions where a score actually
  increased — a naive implementation that logs every state transition
  would pollute a match's point log with timeouts and scoreless side-outs.
  Covered in Task 4.
- Rehydrating a `PickleballGame`/`PickleballMatch` from saved state must
  restore `undo()` capability exactly, not just the current score — a
  crash-recovered game that can't be undone defeats half the purpose of
  saving it. Covered in Tasks 2, 3, and 5 (the full snapshot round-trip).
- `ScoringFormat`'s associated-value case (`.rally(freeze: Bool)`) must
  round-trip through `Codable` with an explicit, stable wire format — the
  default synthesized Codable for an enum with an associated value is not
  something to depend on across a future case rename. Covered in Task 1.
- Saving a second in-progress snapshot must replace the first, not
  accumulate a second row — otherwise `loadInProgressMatch` would have an
  ambiguous "which one" problem after a second app relaunch mid-match.
  Covered in Task 8.

---

## Task 1: Codable Stability for Persisted Engine Types

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/ScoringFormat.swift`
- Modify: `PickleballKit/Sources/PickleballKit/GameConfiguration.swift`
- Modify: `PickleballKit/Sources/PickleballKit/GameState.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/CodableStabilityTests.swift`

**Interfaces:**
- Consumes: `ScoringFormat`, `GameConfiguration`, `GameState` (Phase 1,
  already `Codable` via synthesis).
- Produces: the same three types, still `Codable`, but `ScoringFormat` now
  has a hand-written `init(from:)`/`encode(to:)` with an explicit,
  versioned wire format (`{"kind": "sideOut"}` / `{"kind": "rally", "freeze": true}`)
  instead of relying on synthesis; `GameConfiguration` and `GameState` gain
  explicit `CodingKeys` enums pinning their current property names as the
  wire format. `Team`, `ServerNumber`, `PlayMode`, `WinningScore`,
  `MatchFormat` are all `RawRepresentable` enums and already encode via
  their raw value — no change needed for those.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/CodableStabilityTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class CodableStabilityTests: XCTestCase {
    func testScoringFormatRallyRoundTrips() throws {
        let original = ScoringFormat.rally(freeze: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScoringFormat.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testScoringFormatSideOutRoundTrips() throws {
        let data = try JSONEncoder().encode(ScoringFormat.sideOut)
        let decoded = try JSONDecoder().decode(ScoringFormat.self, from: data)
        XCTAssertEqual(decoded, .sideOut)
    }

    func testScoringFormatHasStableExplicitWireFormat() throws {
        let data = try JSONEncoder().encode(ScoringFormat.rally(freeze: true))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\""))
        XCTAssertTrue(json.contains("\"rally\""))
        XCTAssertTrue(json.contains("\"freeze\""))
    }

    func testGameConfigurationRoundTrips() throws {
        let original = GameConfiguration(
            playMode: .singles,
            scoringFormat: .rally(freeze: true),
            winningScore: .fifteen,
            winByTwo: false,
            timeoutsPerTeam: 1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameConfiguration.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testGameStateRoundTrips() throws {
        let original = GameState(
            teamAScore: 4,
            teamBScore: 7,
            servingTeam: .teamB,
            serverNumber: .two,
            teamATimeoutsRemaining: 1,
            teamBTimeoutsRemaining: 0,
            hasSideSwitched: true,
            lastPointWonWhileServing: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter CodableStabilityTests`
Expected: FAIL — `testScoringFormatHasStableExplicitWireFormat` fails
because the synthesized Codable for `ScoringFormat` does not produce a
`"kind"` key (the other tests likely pass already since synthesis is
*functionally* round-trip-safe today; this task makes the format
explicit and stable, not merely functional).

- [ ] **Step 3: Give ScoringFormat an explicit, hand-written Codable implementation**

Replace the full contents of `PickleballKit/Sources/PickleballKit/ScoringFormat.swift`:

```swift
public enum ScoringFormat: Sendable, Equatable {
    case sideOut
    case rally(freeze: Bool)
}

extension ScoringFormat: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case freeze
    }

    private enum Kind: String, Codable {
        case sideOut
        case rally
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .sideOut:
            self = .sideOut
        case .rally:
            let freeze = try container.decode(Bool.self, forKey: .freeze)
            self = .rally(freeze: freeze)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sideOut:
            try container.encode(Kind.sideOut, forKey: .kind)
        case .rally(let freeze):
            try container.encode(Kind.rally, forKey: .kind)
            try container.encode(freeze, forKey: .freeze)
        }
    }
}
```

- [ ] **Step 4: Add explicit CodingKeys to GameConfiguration**

In `PickleballKit/Sources/PickleballKit/GameConfiguration.swift`, add
inside the struct body (after the initializer):

```swift
    private enum CodingKeys: String, CodingKey {
        case playMode
        case scoringFormat
        case winningScore
        case winByTwo
        case timeoutsPerTeam
    }
```

- [ ] **Step 5: Add explicit CodingKeys to GameState**

In `PickleballKit/Sources/PickleballKit/GameState.swift`, add inside the
struct body (after the `timeoutsRemaining(for:)` method):

```swift
    private enum CodingKeys: String, CodingKey {
        case teamAScore
        case teamBScore
        case servingTeam
        case serverNumber
        case teamATimeoutsRemaining
        case teamBTimeoutsRemaining
        case hasSideSwitched
        case lastPointWonWhileServing
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all `CodableStabilityTests` plus every prior task's test
(56 tests from Phase 1) still pass.

- [ ] **Step 7: Commit**

```bash
git add PickleballKit
git commit -m "feat: pin stable Codable wire format for ScoringFormat, GameConfiguration, GameState"
```

---

## Task 2: PickleballGame Rehydration

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballGameRehydrationTests.swift`

**Interfaces:**
- Consumes: `PickleballGame`'s existing designated init and all Phase 1
  methods (unchanged).
- Produces: `public private(set) var history: [GameState]` (was `private`
  — this is the only change to an existing declaration) and a second
  public initializer `init(configuration:state:history:proUnlocked:demoPointCap:)`
  that reconstructs a game from already-known state and history, with no
  new game-start logic applied.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/PickleballGameRehydrationTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballGameRehydrationTests: XCTestCase {
    func testRehydratedGameRestoresExactStateAndUndoCapability() {
        let original = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        original.recordPoint(for: .teamA)
        original.recordPoint(for: .teamA)

        let resumed = PickleballGame(
            configuration: original.configuration,
            state: original.state,
            history: original.history,
            proUnlocked: original.proUnlocked,
            demoPointCap: original.demoPointCap
        )

        XCTAssertEqual(resumed.state, original.state)
        XCTAssertTrue(resumed.canUndo)
        resumed.undo()
        XCTAssertEqual(resumed.state.teamAScore, 1)
        resumed.undo()
        XCTAssertEqual(resumed.state.teamAScore, 0)
        XCTAssertFalse(resumed.canUndo)
    }

    func testRehydratedGameWithEmptyHistoryCannotUndo() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        let resumed = PickleballGame(configuration: game.configuration, state: game.state, history: [], proUnlocked: true, demoPointCap: nil)
        XCTAssertFalse(resumed.canUndo)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter PickleballGameRehydrationTests`
Expected: FAIL — compiler error, no such initializer, and `history` is
not accessible from outside the module.

- [ ] **Step 3: Add the public history accessor and the resuming initializer**

In `PickleballKit/Sources/PickleballKit/PickleballGame.swift`, change the
`history` declaration:

```swift
    public private(set) var history: [GameState] = []
```

(This replaces the old `private var history: [GameState] = []` line —
same line, just the access level changes; nothing else in the file
references `history` differently.)

Then add a second initializer immediately after the existing one:

```swift
    /// Reconstructs a game from a previously saved state and undo history —
    /// used by the persistence layer to resume an in-progress game after a
    /// crash or relaunch with its undo stack intact.
    public init(
        configuration: GameConfiguration,
        state: GameState,
        history: [GameState],
        proUnlocked: Bool,
        demoPointCap: Int?
    ) {
        self.configuration = configuration
        self.state = state
        self.history = history
        self.proUnlocked = proUnlocked
        self.demoPointCap = demoPointCap
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests, including every Phase 1 test (the `history`
access-level change does not affect any internal usage).

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add PickleballGame rehydration initializer and public history"
```

---

## Task 3: PickleballMatch Rehydration

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballMatch.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballMatchRehydrationTests.swift`

**Interfaces:**
- Consumes: `PickleballGame`'s rehydration initializer (Task 2);
  `PickleballMatch`'s existing designated init and all Phase 1 methods
  (unchanged).
- Produces: a second public initializer
  `init(configuration:matchFormat:completedGames:currentGame:gamesWon:)`
  that reconstructs a match from its already-reconstructed games, with no
  new-match-start logic applied.

- [ ] **Step 1: Write failing test**

Create `PickleballKit/Tests/PickleballKitTests/PickleballMatchRehydrationTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballMatchRehydrationTests: XCTestCase {
    func testRehydratedMatchPreservesCompletedGamesAndCurrentGame() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let original = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { original.recordPoint(for: .teamA) }
        original.recordPoint(for: .teamB)

        let resumed = PickleballMatch(
            configuration: original.configuration,
            matchFormat: original.matchFormat,
            completedGames: original.completedGames,
            currentGame: original.currentGame,
            gamesWon: [.teamA: original.gamesWon(for: .teamA), .teamB: original.gamesWon(for: .teamB)]
        )

        // Game 2 starts with teamA serving (won game 1) at Server 2 (brand
        // new game rule); teamB's recordPoint call is a full side-out, not
        // a score, under the default side-out scoring format.
        XCTAssertEqual(resumed.completedGames.count, 1)
        XCTAssertEqual(resumed.gamesWon(for: .teamA), 1)
        XCTAssertEqual(resumed.currentGame.state.teamBScore, 0)
        XCTAssertEqual(resumed.currentGame.state.servingTeam, .teamB)
        XCTAssertTrue(resumed.currentGame.canUndo)
        resumed.undo()
        XCTAssertEqual(resumed.currentGame.state.servingTeam, .teamA)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter PickleballMatchRehydrationTests`
Expected: FAIL — compiler error, no such initializer.

- [ ] **Step 3: Add the resuming initializer**

In `PickleballKit/Sources/PickleballKit/PickleballMatch.swift`, add a
second initializer immediately after the existing one:

```swift
    /// Reconstructs a match from its already-reconstructed games — used by
    /// the persistence layer to resume a saved in-progress match after a
    /// crash or relaunch.
    public init(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        completedGames: [PickleballGame],
        currentGame: PickleballGame,
        gamesWon: [Team: Int]
    ) {
        self.configuration = configuration
        self.matchFormat = matchFormat
        self.completedGames = completedGames
        self.currentGame = currentGame
        self.gamesWon = gamesWon
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add PickleballMatch rehydration initializer"
```

---

## Task 4: Point Event Derivation

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/Persistence/PointEventDerivation.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/PointEventDerivationTests.swift`

**Interfaces:**
- Consumes: `GameState`, `Team` (Phase 1); `PickleballGame.history`/`.state`
  (Task 2, for use in tests — this task's function itself only takes plain
  `[GameState]`/`GameState` parameters, no dependency on `PickleballGame`).
- Produces: `public struct DerivedPointEvent: Equatable, Sendable` with
  `sequenceNumber: Int`, `scoringTeam: Team`, `teamAScoreAfter: Int`,
  `teamBScoreAfter: Int`; and
  `public func derivePointEvents(history: [GameState], finalState: GameState) -> [DerivedPointEvent]`.
  Task 9 consumes this function directly.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/PointEventDerivationTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PointEventDerivationTests: XCTestCase {
    func testDerivePointEventsSkipsNonScoringTransitions() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false))
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        game.recordPoint(for: .teamA)
        game.requestTimeout(for: .teamB)
        game.recordPoint(for: .teamB)

        let events = derivePointEvents(history: game.history, finalState: game.state)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], DerivedPointEvent(sequenceNumber: 1, scoringTeam: .teamA, teamAScoreAfter: 1, teamBScoreAfter: 0))
        XCTAssertEqual(events[1], DerivedPointEvent(sequenceNumber: 2, scoringTeam: .teamB, teamAScoreAfter: 1, teamBScoreAfter: 1))
    }

    func testDerivePointEventsWithNoHistoryReturnsEmpty() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        let events = derivePointEvents(history: game.history, finalState: game.state)
        XCTAssertTrue(events.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter PointEventDerivationTests`
Expected: FAIL — "cannot find 'DerivedPointEvent'/'derivePointEvents' in scope".

- [ ] **Step 3: Implement derivePointEvents**

Create `PickleballKit/Sources/PickleballKit/Persistence/PointEventDerivation.swift`:

```swift
public struct DerivedPointEvent: Equatable, Sendable {
    public let sequenceNumber: Int
    public let scoringTeam: Team
    public let teamAScoreAfter: Int
    public let teamBScoreAfter: Int

    public init(sequenceNumber: Int, scoringTeam: Team, teamAScoreAfter: Int, teamBScoreAfter: Int) {
        self.sequenceNumber = sequenceNumber
        self.scoringTeam = scoringTeam
        self.teamAScoreAfter = teamAScoreAfter
        self.teamBScoreAfter = teamBScoreAfter
    }
}

/// Derives a point-by-point log from a game's state history. Only
/// transitions where a team's score actually increased become events —
/// timeouts, side-out rotations with no score change, and no-op corrections
/// are not "scored points" and are intentionally excluded.
public func derivePointEvents(history: [GameState], finalState: GameState) -> [DerivedPointEvent] {
    let allStates = history + [finalState]
    guard allStates.count > 1 else { return [] }

    var events: [DerivedPointEvent] = []
    var sequenceNumber = 0
    for index in 1..<allStates.count {
        let before = allStates[index - 1]
        let after = allStates[index]

        let scoringTeam: Team
        if after.teamAScore > before.teamAScore {
            scoringTeam = .teamA
        } else if after.teamBScore > before.teamBScore {
            scoringTeam = .teamB
        } else {
            continue
        }

        sequenceNumber += 1
        events.append(DerivedPointEvent(
            sequenceNumber: sequenceNumber,
            scoringTeam: scoringTeam,
            teamAScoreAfter: after.teamAScore,
            teamBScoreAfter: after.teamBScore
        ))
    }
    return events
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add point event derivation from game history"
```

---

## Task 5: MatchSnapshot (Codable Round-Trip DTO)

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/Persistence/MatchSnapshot.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/MatchSnapshotTests.swift`

**Interfaces:**
- Consumes: `PickleballGame`'s rehydration init (Task 2), `PickleballMatch`'s
  rehydration init (Task 3), `PickleballMatch.gamesWon(for:)` (Phase 1).
- Produces: `public struct MatchSnapshot: Codable, Equatable, Sendable`
  (with nested `GameSnapshot`), `extension PickleballMatch { public var
  snapshot: MatchSnapshot { get } }`, and
  `extension PickleballMatch { public convenience init(resuming: MatchSnapshot) }`.
  Task 8 consumes `snapshot` and `init(resuming:)` directly.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/MatchSnapshotTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class MatchSnapshotTests: XCTestCase {
    func testMatchSnapshotRoundTripPreservesStateAndUndoCapability() throws {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let original = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { original.recordPoint(for: .teamA) }
        original.recordPoint(for: .teamB)
        original.recordPoint(for: .teamB)

        let data = try JSONEncoder().encode(original.snapshot)
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        let resumed = PickleballMatch(resuming: decoded)

        // Game 2: teamA serves first (won game 1) at Server 2. teamB's first
        // recordPoint is a full side-out (no score, serve passes to teamB);
        // teamB's second recordPoint is then a real score as the new server.
        XCTAssertEqual(resumed.completedGames.count, 1)
        XCTAssertEqual(resumed.gamesWon(for: .teamA), 1)
        XCTAssertEqual(resumed.currentGame.state.teamBScore, 1)
        XCTAssertTrue(resumed.currentGame.canUndo)
        resumed.undo()
        XCTAssertEqual(resumed.currentGame.state.teamBScore, 0)
    }

    func testMatchSnapshotRoundTripOfFreshMatch() throws {
        let original = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        let data = try JSONEncoder().encode(original.snapshot)
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: data)
        let resumed = PickleballMatch(resuming: decoded)
        XCTAssertEqual(resumed.currentGame.state.teamAScore, 0)
        XCTAssertFalse(resumed.currentGame.proUnlocked)
        XCTAssertEqual(resumed.currentGame.demoPointCap, 5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter MatchSnapshotTests`
Expected: FAIL — "cannot find 'MatchSnapshot' in scope".

- [ ] **Step 3: Implement MatchSnapshot and the snapshot/resuming extension**

Create `PickleballKit/Sources/PickleballKit/Persistence/MatchSnapshot.swift`:

```swift
public struct MatchSnapshot: Codable, Equatable, Sendable {
    public struct GameSnapshot: Codable, Equatable, Sendable {
        public var state: GameState
        public var history: [GameState]

        public init(state: GameState, history: [GameState]) {
            self.state = state
            self.history = history
        }
    }

    public var configuration: GameConfiguration
    public var matchFormat: MatchFormat
    public var proUnlocked: Bool
    public var demoPointCap: Int?
    public var completedGames: [GameSnapshot]
    public var currentGame: GameSnapshot
    public var gamesWonTeamA: Int
    public var gamesWonTeamB: Int

    public init(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        proUnlocked: Bool,
        demoPointCap: Int?,
        completedGames: [GameSnapshot],
        currentGame: GameSnapshot,
        gamesWonTeamA: Int,
        gamesWonTeamB: Int
    ) {
        self.configuration = configuration
        self.matchFormat = matchFormat
        self.proUnlocked = proUnlocked
        self.demoPointCap = demoPointCap
        self.completedGames = completedGames
        self.currentGame = currentGame
        self.gamesWonTeamA = gamesWonTeamA
        self.gamesWonTeamB = gamesWonTeamB
    }
}

extension PickleballMatch {
    public var snapshot: MatchSnapshot {
        MatchSnapshot(
            configuration: configuration,
            matchFormat: matchFormat,
            proUnlocked: currentGame.proUnlocked,
            demoPointCap: currentGame.demoPointCap,
            completedGames: completedGames.map {
                MatchSnapshot.GameSnapshot(state: $0.state, history: $0.history)
            },
            currentGame: MatchSnapshot.GameSnapshot(state: currentGame.state, history: currentGame.history),
            gamesWonTeamA: gamesWon(for: .teamA),
            gamesWonTeamB: gamesWon(for: .teamB)
        )
    }

    public convenience init(resuming snapshot: MatchSnapshot) {
        let completed = snapshot.completedGames.map { gameSnapshot in
            PickleballGame(
                configuration: snapshot.configuration,
                state: gameSnapshot.state,
                history: gameSnapshot.history,
                proUnlocked: snapshot.proUnlocked,
                demoPointCap: snapshot.demoPointCap
            )
        }
        let current = PickleballGame(
            configuration: snapshot.configuration,
            state: snapshot.currentGame.state,
            history: snapshot.currentGame.history,
            proUnlocked: snapshot.proUnlocked,
            demoPointCap: snapshot.demoPointCap
        )
        self.init(
            configuration: snapshot.configuration,
            matchFormat: snapshot.matchFormat,
            completedGames: completed,
            currentGame: current,
            gamesWon: [.teamA: snapshot.gamesWonTeamA, .teamB: snapshot.gamesWonTeamB]
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add MatchSnapshot Codable DTO for match rehydration"
```

---

## Task 6: SwiftData Models — Completed Match History

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/Persistence/TeamSide.swift`
- Create: `PickleballKit/Sources/PickleballKit/Persistence/MatchRecord.swift`
- Create: `PickleballKit/Sources/PickleballKit/Persistence/GameRecord.swift`
- Create: `PickleballKit/Sources/PickleballKit/Persistence/PointEvent.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/PersistenceModelsTests.swift`

**Interfaces:**
- Consumes: `Team`, `MatchFormat` (Phase 1).
- Produces: four `@Model` classes. `TeamSide` (`team: Team`,
  `displayName: String`, `match: MatchRecord?`). `MatchRecord` (`id`,
  `startedAt`, `completedAt`, `matchFormat: MatchFormat`,
  `winningTeam: Team`, `configurationData: Data`, `teamSides: [TeamSide]?`,
  `games: [GameRecord]?`). `GameRecord` (`id`, `gameNumber`,
  `teamAFinalScore`, `teamBFinalScore`, `winningTeam: Team`, `match:
  MatchRecord?`, `points: [PointEvent]?`, and `orderedPoints: [PointEvent]`
  — see the ordering constraint above). `PointEvent` (`id`,
  `sequenceNumber`, `scoringTeam: Team`, `teamAScoreAfter`,
  `teamBScoreAfter`, `game: GameRecord?`). Task 7/9 consume all four.

- [ ] **Step 1: Write failing test**

Create `PickleballKit/Tests/PickleballKitTests/PersistenceModelsTests.swift`:

```swift
import XCTest
import SwiftData
@testable import PickleballKit

final class PersistenceModelsTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TeamSide.self, MatchRecord.self, GameRecord.self, PointEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    func testMatchRecordWithRelationshipsPersistsAndReloads() throws {
        let context = try makeInMemoryContext()

        let record = MatchRecord(
            startedAt: Date(),
            completedAt: Date(),
            matchFormat: .bestOfThree,
            winningTeam: .teamA,
            configurationData: Data()
        )
        let teamA = TeamSide(team: .teamA, displayName: "The Smashers")
        let teamB = TeamSide(team: .teamB, displayName: "Net Ninjas")
        teamA.match = record
        teamB.match = record
        record.teamSides = [teamA, teamB]

        let game = GameRecord(gameNumber: 1, teamAFinalScore: 11, teamBFinalScore: 7, winningTeam: .teamA)
        game.match = record
        let point = PointEvent(sequenceNumber: 1, scoringTeam: .teamA, teamAScoreAfter: 1, teamBScoreAfter: 0)
        point.game = game
        game.points = [point]
        record.games = [game]

        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MatchRecord>())
        XCTAssertEqual(fetched.count, 1)
        let reloaded = try XCTUnwrap(fetched.first)
        XCTAssertEqual(reloaded.winningTeam, .teamA)
        XCTAssertEqual(reloaded.teamSides?.count, 2)
        XCTAssertEqual(reloaded.games?.count, 1)
        XCTAssertEqual(reloaded.games?.first?.points?.count, 1)
        XCTAssertEqual(reloaded.games?.first?.points?.first?.scoringTeam, .teamA)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "PickleballKit" && swift test --filter PersistenceModelsTests`
Expected: FAIL — "cannot find 'TeamSide'/'MatchRecord'/'GameRecord'/'PointEvent' in scope".

- [ ] **Step 3: Implement the four models**

Create `PickleballKit/Sources/PickleballKit/Persistence/TeamSide.swift`:

```swift
import SwiftData

@Model
public final class TeamSide {
    public var teamRawValue: String = Team.teamA.rawValue
    public var displayName: String = ""
    public var match: MatchRecord?

    public init(team: Team, displayName: String) {
        self.teamRawValue = team.rawValue
        self.displayName = displayName
    }

    public var team: Team {
        Team(rawValue: teamRawValue) ?? .teamA
    }
}
```

Create `PickleballKit/Sources/PickleballKit/Persistence/MatchRecord.swift`:

```swift
import SwiftData
import Foundation

@Model
public final class MatchRecord {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    public var completedAt: Date = Date()
    public var matchFormatRawValue: Int = MatchFormat.bestOfOne.rawValue
    public var winningTeamRawValue: String = Team.teamA.rawValue
    public var configurationData: Data = Data()

    @Relationship(deleteRule: .cascade, inverse: \TeamSide.match)
    public var teamSides: [TeamSide]? = []

    @Relationship(deleteRule: .cascade, inverse: \GameRecord.match)
    public var games: [GameRecord]? = []

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        completedAt: Date,
        matchFormat: MatchFormat,
        winningTeam: Team,
        configurationData: Data
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.matchFormatRawValue = matchFormat.rawValue
        self.winningTeamRawValue = winningTeam.rawValue
        self.configurationData = configurationData
    }

    public var matchFormat: MatchFormat {
        MatchFormat(rawValue: matchFormatRawValue) ?? .bestOfOne
    }

    public var winningTeam: Team {
        Team(rawValue: winningTeamRawValue) ?? .teamA
    }
}
```

Create `PickleballKit/Sources/PickleballKit/Persistence/GameRecord.swift`:

```swift
import SwiftData
import Foundation

@Model
public final class GameRecord {
    public var id: UUID = UUID()
    public var gameNumber: Int = 1
    public var teamAFinalScore: Int = 0
    public var teamBFinalScore: Int = 0
    public var winningTeamRawValue: String = Team.teamA.rawValue
    public var match: MatchRecord?

    /// SwiftData to-many relationship arrays have no guaranteed order —
    /// do not rely on this array's order directly (in particular, `.last`
    /// is not "the most recent point"). Use `orderedPoints` instead.
    @Relationship(deleteRule: .cascade, inverse: \PointEvent.game)
    public var points: [PointEvent]? = []

    /// `points` sorted by `sequenceNumber` — use this, not `points`
    /// directly, whenever point order matters (e.g. a point-by-point log).
    public var orderedPoints: [PointEvent] {
        (points ?? []).sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    public init(
        id: UUID = UUID(),
        gameNumber: Int,
        teamAFinalScore: Int,
        teamBFinalScore: Int,
        winningTeam: Team
    ) {
        self.id = id
        self.gameNumber = gameNumber
        self.teamAFinalScore = teamAFinalScore
        self.teamBFinalScore = teamBFinalScore
        self.winningTeamRawValue = winningTeam.rawValue
    }

    public var winningTeam: Team {
        Team(rawValue: winningTeamRawValue) ?? .teamA
    }
}
```

Create `PickleballKit/Sources/PickleballKit/Persistence/PointEvent.swift`:

```swift
import SwiftData
import Foundation

@Model
public final class PointEvent {
    public var id: UUID = UUID()
    public var sequenceNumber: Int = 0
    public var scoringTeamRawValue: String = Team.teamA.rawValue
    public var teamAScoreAfter: Int = 0
    public var teamBScoreAfter: Int = 0
    public var game: GameRecord?

    public init(
        id: UUID = UUID(),
        sequenceNumber: Int,
        scoringTeam: Team,
        teamAScoreAfter: Int,
        teamBScoreAfter: Int
    ) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.scoringTeamRawValue = scoringTeam.rawValue
        self.teamAScoreAfter = teamAScoreAfter
        self.teamBScoreAfter = teamBScoreAfter
    }

    public var scoringTeam: Team {
        Team(rawValue: scoringTeamRawValue) ?? .teamA
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add SwiftData models for completed match history"
```

---

## Task 7: SwiftData In-Progress Model + PersistenceContainer

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/Persistence/InProgressGameState.swift`
- Create: `PickleballKit/Sources/PickleballKit/Persistence/PersistenceContainer.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/PersistenceContainerTests.swift`

**Interfaces:**
- Consumes: `TeamSide`, `MatchRecord`, `GameRecord`, `PointEvent` (Task 6).
- Produces: `@Model public final class InProgressGameState` (`id`,
  `updatedAt: Date`, `snapshotData: Data`), and
  `public enum PersistenceContainer` with
  `public static let cloudKitContainerIdentifier: String`,
  `public static func makeContainer() throws -> ModelContainer` (the real,
  CloudKit-backed container), and
  `public static func makeInMemoryContainer() throws -> ModelContainer`
  (for tests — no CloudKit, no disk). Tasks 8/9 consume
  `makeInMemoryContainer()` directly in their tests.

- [ ] **Step 1: Write failing test**

Create `PickleballKit/Tests/PickleballKitTests/PersistenceContainerTests.swift`:

```swift
import XCTest
import SwiftData
@testable import PickleballKit

final class PersistenceContainerTests: XCTestCase {
    func testInMemoryContainerSupportsBothSchemas() throws {
        let container = try PersistenceContainer.makeInMemoryContainer()
        let context = ModelContext(container)

        let record = InProgressGameState(updatedAt: Date(), snapshotData: Data())
        context.insert(record)

        let match = MatchRecord(startedAt: Date(), completedAt: Date(), matchFormat: .bestOfOne, winningTeam: .teamA, configurationData: Data())
        context.insert(match)

        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<InProgressGameState>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MatchRecord>()).count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "PickleballKit" && swift test --filter PersistenceContainerTests`
Expected: FAIL — "cannot find 'InProgressGameState'/'PersistenceContainer' in scope".

- [ ] **Step 3: Implement InProgressGameState and PersistenceContainer**

Create `PickleballKit/Sources/PickleballKit/Persistence/InProgressGameState.swift`:

```swift
import SwiftData
import Foundation

/// A local-only, crash-recovery snapshot of the currently-live match.
/// Deliberately excluded from the CloudKit schema (see `PersistenceContainer`)
/// — it exists purely to resume this device's in-flight game after a crash
/// or relaunch, never to sync or be browsed.
@Model
public final class InProgressGameState {
    public var id: UUID = UUID()
    public var updatedAt: Date = Date()
    public var snapshotData: Data = Data()

    public init(id: UUID = UUID(), updatedAt: Date, snapshotData: Data) {
        self.id = id
        self.updatedAt = updatedAt
        self.snapshotData = snapshotData
    }
}
```

Create `PickleballKit/Sources/PickleballKit/Persistence/PersistenceContainer.swift`:

```swift
import SwiftData
import Foundation

public enum PersistenceContainer {
    public static let cloudKitContainerIdentifier = "iCloud.com.delonsampaio.ServerTwo"

    private static var historySchema: Schema {
        Schema([TeamSide.self, MatchRecord.self, GameRecord.self, PointEvent.self])
    }

    private static var inProgressSchema: Schema {
        Schema([InProgressGameState.self])
    }

    private static var fullSchema: Schema {
        Schema([TeamSide.self, MatchRecord.self, GameRecord.self, PointEvent.self, InProgressGameState.self])
    }

    /// The real container used by the app: completed-match history syncs via
    /// CloudKit, the in-progress snapshot stays local-only.
    public static func makeContainer() throws -> ModelContainer {
        let historyConfiguration = ModelConfiguration(
            "History",
            schema: historySchema,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        let inProgressConfiguration = ModelConfiguration(
            "InProgress",
            schema: inProgressSchema,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: historyConfiguration, inProgressConfiguration)
    }

    /// An in-memory container with no CloudKit involvement, for tests. Each
    /// call gets uniquely-named configurations — reusing a fixed name like
    /// "History" across many in-memory containers in the same test process
    /// causes SwiftData to bleed state between what should be isolated
    /// containers.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let suffix = UUID().uuidString
        let historyConfiguration = ModelConfiguration(
            "History-\(suffix)",
            schema: historySchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let inProgressConfiguration = ModelConfiguration(
            "InProgress-\(suffix)",
            schema: inProgressSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: historyConfiguration, inProgressConfiguration)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add InProgressGameState model and PersistenceContainer"
```

---

## Task 8: MatchRepository — In-Progress Snapshot

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/MatchRepositoryInProgressTests.swift`

**Interfaces:**
- Consumes: `PersistenceContainer.makeInMemoryContainer()` (Task 7),
  `InProgressGameState` (Task 7), `PickleballMatch.snapshot`/
  `init(resuming:)` (Task 5).
- Produces: `public final class MatchRepository` with
  `public init(modelContext: ModelContext)`,
  `public func saveInProgressSnapshot(for match: PickleballMatch) throws`,
  `public func loadInProgressMatch() throws -> PickleballMatch?`,
  `public func clearInProgressSnapshot() throws`. Task 9 adds the
  completed-match methods to this same class.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/MatchRepositoryInProgressTests.swift`:

```swift
import XCTest
import SwiftData
@testable import PickleballKit

final class MatchRepositoryInProgressTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    func testSaveAndLoadInProgressSnapshotRoundTrips() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        match.recordPoint(for: .teamA)
        match.recordPoint(for: .teamA)

        try repository.saveInProgressSnapshot(for: match)

        let loaded = try repository.loadInProgressMatch()
        let resumedMatch = try XCTUnwrap(loaded)
        XCTAssertEqual(resumedMatch.currentGame.state.teamAScore, 2)
        XCTAssertTrue(resumedMatch.currentGame.canUndo)
    }

    func testSavingASecondSnapshotReplacesTheFirstRatherThanAccumulating() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let firstMatch = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        firstMatch.recordPoint(for: .teamA)
        try repository.saveInProgressSnapshot(for: firstMatch)

        let secondMatch = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamB, proUnlocked: true, demoPointCap: nil)
        secondMatch.recordPoint(for: .teamB)
        secondMatch.recordPoint(for: .teamB)
        try repository.saveInProgressSnapshot(for: secondMatch)

        let allRecords = try context.fetch(FetchDescriptor<InProgressGameState>())
        XCTAssertEqual(allRecords.count, 1)

        let loaded = try repository.loadInProgressMatch()
        let resumedMatch = try XCTUnwrap(loaded)
        XCTAssertEqual(resumedMatch.currentGame.state.teamBScore, 2)
    }

    func testLoadWithNoSavedSnapshotReturnsNil() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let loaded = try repository.loadInProgressMatch()
        XCTAssertNil(loaded)
    }

    func testClearInProgressSnapshotRemovesIt() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        try repository.saveInProgressSnapshot(for: match)
        try repository.clearInProgressSnapshot()
        let loaded = try repository.loadInProgressMatch()
        XCTAssertNil(loaded)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter MatchRepositoryInProgressTests`
Expected: FAIL — "cannot find 'MatchRepository' in scope".

- [ ] **Step 3: Implement MatchRepository (in-progress methods only)**

Create `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`:

```swift
import SwiftData
import Foundation

public enum MatchRepositoryError: Error, Equatable {
    case matchNotOver
}

/// Wraps all SwiftData access for match persistence. UI code should never
/// touch `ModelContext` directly — it goes through this type instead.
public final class MatchRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: In-progress snapshot (crash recovery)

    public func saveInProgressSnapshot(for match: PickleballMatch) throws {
        let data = try JSONEncoder().encode(match.snapshot)
        try clearInProgressSnapshot()
        let record = InProgressGameState(updatedAt: Date(), snapshotData: data)
        modelContext.insert(record)
        try modelContext.save()
    }

    public func loadInProgressMatch() throws -> PickleballMatch? {
        let existing = try modelContext.fetch(FetchDescriptor<InProgressGameState>())
        guard let record = existing.first else { return nil }
        let snapshot = try JSONDecoder().decode(MatchSnapshot.self, from: record.snapshotData)
        return PickleballMatch(resuming: snapshot)
    }

    public func clearInProgressSnapshot() throws {
        let existing = try modelContext.fetch(FetchDescriptor<InProgressGameState>())
        for stale in existing {
            modelContext.delete(stale)
        }
        try modelContext.save()
    }
}
```

(`MatchRepositoryError` is declared here even though it's only used by
Task 9's methods — it lives with the type it belongs to, and this file is
the natural home for it.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add MatchRepository in-progress snapshot save/load/clear"
```

---

## Task 9: MatchRepository — Completed Match History

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/MatchRepositoryHistoryTests.swift`

**Interfaces:**
- Consumes: `MatchRepository` (Task 8, adds methods to the same class);
  `derivePointEvents` (Task 4); `TeamSide`/`MatchRecord`/`GameRecord`/
  `PointEvent`/`GameRecord.orderedPoints` (Task 6).
- Produces: `public func saveCompletedMatch(_:teamAName:teamBName:startedAt:completedAt:) throws -> MatchRecord`
  and `public func fetchMatchHistory() throws -> [MatchRecord]` added to
  `MatchRepository`. This is the last task of the plan — `MatchRepository`
  is complete after this task.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/MatchRepositoryHistoryTests.swift`:

```swift
import XCTest
import SwiftData
@testable import PickleballKit

final class MatchRepositoryHistoryTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    func testSaveCompletedMatchPersistsFullGraph() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        let saved = try repository.saveCompletedMatch(match, teamAName: "The Smashers", teamBName: "Net Ninjas", startedAt: Date())

        XCTAssertEqual(saved.winningTeam, .teamA)
        XCTAssertEqual(saved.teamSides?.count, 2)
        XCTAssertEqual(saved.games?.count, 1)
        // Relationship arrays have no guaranteed order — orderedPoints
        // sorts by sequenceNumber explicitly.
        let points = try XCTUnwrap(saved.games?.first).orderedPoints
        XCTAssertEqual(points.count, 11)
        XCTAssertEqual(points.last?.teamAScoreAfter, 11)
    }

    func testSaveCompletedMatchThrowsIfMatchIsNotOver() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        match.recordPoint(for: .teamA)

        XCTAssertThrowsError(try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())) { error in
            XCTAssertEqual(error as? MatchRepositoryError, .matchNotOver)
        }
    }

    func testFetchMatchHistoryReturnsNewestFirst() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let earlierMatch = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { earlierMatch.recordPoint(for: .teamA) }
        _ = try repository.saveCompletedMatch(earlierMatch, teamAName: "A", teamBName: "B", startedAt: Date(timeIntervalSince1970: 1000), completedAt: Date(timeIntervalSince1970: 2000))

        let laterMatch = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamB, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { laterMatch.recordPoint(for: .teamB) }
        _ = try repository.saveCompletedMatch(laterMatch, teamAName: "A", teamBName: "B", startedAt: Date(timeIntervalSince1970: 3000), completedAt: Date(timeIntervalSince1970: 4000))

        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.winningTeam, .teamB)
        XCTAssertEqual(history.last?.winningTeam, .teamA)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test --filter MatchRepositoryHistoryTests`
Expected: FAIL — "value of type 'MatchRepository' has no member 'saveCompletedMatch'/'fetchMatchHistory'".

- [ ] **Step 3: Add the completed-match methods**

In `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`,
add these methods inside the `MatchRepository` class, after
`clearInProgressSnapshot()`:

```swift
    // MARK: Completed match history

    @discardableResult
    public func saveCompletedMatch(
        _ match: PickleballMatch,
        teamAName: String,
        teamBName: String,
        startedAt: Date,
        completedAt: Date = Date()
    ) throws -> MatchRecord {
        guard let winner = match.matchWinner else {
            throw MatchRepositoryError.matchNotOver
        }

        let configurationData = try JSONEncoder().encode(match.configuration)
        let record = MatchRecord(
            startedAt: startedAt,
            completedAt: completedAt,
            matchFormat: match.matchFormat,
            winningTeam: winner,
            configurationData: configurationData
        )

        // Every object in the graph is inserted explicitly rather than
        // relying on SwiftData to cascade-insert objects reachable only
        // through a relationship — that cascade is unreliable for larger
        // nested graphs (observed dropping PointEvent rows nondeterministically
        // when only the root MatchRecord was inserted).
        modelContext.insert(record)

        let teamASide = TeamSide(team: .teamA, displayName: teamAName)
        let teamBSide = TeamSide(team: .teamB, displayName: teamBName)
        teamASide.match = record
        teamBSide.match = record
        record.teamSides = [teamASide, teamBSide]
        modelContext.insert(teamASide)
        modelContext.insert(teamBSide)

        var gameRecords: [GameRecord] = []
        for (index, game) in match.completedGames.enumerated() {
            guard let gameWinner = game.gameWinner else { continue }
            let gameRecord = GameRecord(
                gameNumber: index + 1,
                teamAFinalScore: game.state.teamAScore,
                teamBFinalScore: game.state.teamBScore,
                winningTeam: gameWinner
            )
            gameRecord.match = record
            modelContext.insert(gameRecord)

            let events = derivePointEvents(history: game.history, finalState: game.state)
            gameRecord.points = events.map { event in
                let point = PointEvent(
                    sequenceNumber: event.sequenceNumber,
                    scoringTeam: event.scoringTeam,
                    teamAScoreAfter: event.teamAScoreAfter,
                    teamBScoreAfter: event.teamBScoreAfter
                )
                point.game = gameRecord
                modelContext.insert(point)
                return point
            }
            gameRecords.append(gameRecord)
        }
        record.games = gameRecords

        try modelContext.save()
        return record
    }

    public func fetchMatchHistory() throws -> [MatchRecord] {
        let descriptor = FetchDescriptor<MatchRecord>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests across all 9 tasks (77 tests total: 56 from
Phase 1 plus 21 new in this plan).

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add MatchRepository completed-match save and history fetch"
```

---

## Final Verification

- [ ] Run the full suite one more time:

Run: `cd "PickleballKit" && swift test`
Expected: PASS, all 77 tests.

- [ ] Run the full suite 3-5 times in a row to confirm determinism — this
  plan's persistence layer was specifically verified against a real
  nondeterminism bug during authoring (see Global Constraints), so a
  single green run is not sufficient confidence here the way it was for
  Phase 1's pure-logic engine.

- [ ] Push the branch and confirm the GitHub Actions workflow passes on
  the PR before merging to `main`.
