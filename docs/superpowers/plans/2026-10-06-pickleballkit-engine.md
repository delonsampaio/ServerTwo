# PickleballKit Core Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and exhaustively test `PickleballKit`, the pure-Swift scoring
engine (doubles/singles, side-out/rally scoring, best-of-N matches, undo,
demo-cap enforcement) that every other part of Server Two depends on.

**Architecture:** A standalone local Swift Package (`PickleballKit/`) with
zero UI or persistence dependencies, developed and tested entirely via
`swift test` — no Xcode project wiring needed yet. `PickleballGame` owns a
single game's rules and a state-history stack for undo; `PickleballMatch`
wraps 1/3/5 games into a match and handles cross-game undo. Wiring this
package into the iOS/Watch/Widget Xcode targets happens in later phases
(3, 5, 6) when each target actually needs it.

**Tech Stack:** Swift 6.4 (Xcode 27 toolchain, confirmed installed), Swift
Package Manager, the `Observation` framework (`@Observable`), XCTest,
GitHub Actions (`macos-15` runner).

**Spec:** `docs/superpowers/specs/2026-10-06-server-two-design.md`
(Sections 1, 2 "Engine / rules", 3.2, 5)

## Global Constraints

- Games are played to 11, 15, or 21, win by 2 (configurable toggle) — Spec §2.
- A brand-new game's first serving team always starts at Server 2 in
  doubles (this applies to every new game in a match, not just game 1 of
  the match) — Spec §2/§3.2, original product requirement.
- Side-switch thresholds are 6 (games to 11), 8 (games to 15), 11 (games to
  21) — Spec §2. Formula used: `ceil(winningScore / 2)`.
- Best-of-1/3/5 match formats — Spec §2.
- The demo point-cap (free vs. $1.99 Pro Unlock) is enforced exactly once,
  inside the engine, via `proUnlocked`/`demoPointCap` — Spec §1, §3.2. No
  other layer re-implements this gate.
- `PickleballKit` has zero persistence or UI imports — Spec §3.2.
- Timeout count per team is not pinned to a specific number in the spec;
  this plan defaults to 2 per team (standard tournament rule) as a
  `GameConfiguration` value the UI can override later — documented
  assumption, not a spec requirement.
- Package platform floor is set conservatively (`.iOS(.v17)`,
  `.watchOS(.v10)`, `.macOS(.v14)` — the minimum needed for `@Observable`)
  rather than guessing at a newer enum case that may not exist in this
  `PackageDescription` version; the shipping app's actual "latest OS only"
  deployment target (Spec §2 risk notes) is set at the Xcode project level
  in later phases, not in this package. The `.macOS(.v14)` entry is not
  about shipping on macOS — it's required because `swift test` compiles
  and runs for the host Mac, and `@Observable` needs macOS 14+; without it,
  SwiftPM defaults to a much older macOS deployment target and every build
  fails. **This was verified against a real build during plan review**
  (see note at the end of Task 1).

## Review Focus

- A doubles game with a long run of consecutive points to the same server
  (e.g. 10 straight rallies won by the serving team) must never misfire the
  Server 1 → Server 2 → side-out rotation — naive off-by-one rotation bugs
  are the single likeliest source of visible, embarrassing bugs in this
  app. Covered in Task 4.
- Win-by-two must correctly extend play past the configured winning score
  (e.g. 10-10 does not end the game, 12-10 does) rather than capping at the
  raw target score. Covered in Task 6 (rally scoring is the cleanest place
  to pin exact tight-margin arithmetic; Task 4 confirms win-by-two also
  composes correctly with side-out scoring at a wide margin).
- Manual score correction must be able to reverse a game that has already
  reported a winner back to "in progress" — real disputes are often about
  the final point, not an earlier one. Covered in Task 8.
- Undoing a point that drops the score back below the demo point-cap must
  immediately unblock scoring again, with no stale "paywalled" state
  surviving the undo. Covered in Task 9.
- Undoing across a completed-game boundary in a multi-game match must
  restore the exact prior game's score/server/timeout state (not just
  decrement a game-won counter and start a blank game). Covered in Task 10.

---

## Task 1: Package Scaffold + CI

**Files:**
- Create: `PickleballKit/Package.swift`
- Create: `PickleballKit/Sources/PickleballKit/PickleballKit.swift`
- Create: `PickleballKit/Tests/PickleballKitTests/PickleballKitTests.swift`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a buildable, testable Swift package named `PickleballKit` with
  target `PickleballKit` and test target `PickleballKitTests`, wired into
  GitHub Actions CI.

- [ ] **Step 1: Create the package manifest**

Create `PickleballKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PickleballKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PickleballKit", targets: ["PickleballKit"])
    ],
    targets: [
        .target(name: "PickleballKit"),
        .testTarget(name: "PickleballKitTests", dependencies: ["PickleballKit"])
    ]
)
```

- [ ] **Step 2: Create a trivial source file so the target builds**

Create `PickleballKit/Sources/PickleballKit/PickleballKit.swift`:

```swift
// PickleballKit: the pure-Swift pickleball scoring engine.
// No UI or persistence imports belong in this module.
```

- [ ] **Step 3: Write a smoke test**

Create `PickleballKit/Tests/PickleballKitTests/PickleballKitTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballKitTests: XCTestCase {
    func testPackageBuildsAndLinksTestTarget() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd "PickleballKit" && swift test`
Expected: `PickleballKitTests` runs and passes (1 test).

- [ ] **Step 5: Add the GitHub Actions CI workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test-pickleball-kit:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Run PickleballKit tests
        working-directory: PickleballKit
        run: swift test
```

- [ ] **Step 6: Commit**

```bash
git add PickleballKit .github/workflows/ci.yml
git commit -m "chore: scaffold PickleballKit package and CI"
```

> **Plan-review note:** every source and test file in this plan (Tasks
> 1-10, final combined state) was actually built and run with `swift test`
> during plan review, not just read for plausibility. That caught two real
> bugs before handoff: (1) without `.macOS(.v14)` in `Package.swift`,
> `swift test` fails outright because it compiles for the host Mac and
> `@Observable` needs macOS 14+ — fixed by adding it above; (2) a win-by-two
> test in Task 4 tried to drive an exact score through doubles side-out
> rotation by hand and was simply wrong about how side-out scoring works
> (a receiving team never scores directly, only gains serve) — removed
> from Task 4 in favor of Task 6's rally-scoring version of that test,
> which exercises the same arithmetic without side-out's rotation
> complexity. All 41 tests across the full plan pass as written below.

---

## Task 2: Core Types & Configuration

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/Team.swift`
- Create: `PickleballKit/Sources/PickleballKit/ServerNumber.swift`
- Create: `PickleballKit/Sources/PickleballKit/PlayMode.swift`
- Create: `PickleballKit/Sources/PickleballKit/ScoringFormat.swift`
- Create: `PickleballKit/Sources/PickleballKit/WinningScore.swift`
- Create: `PickleballKit/Sources/PickleballKit/MatchFormat.swift`
- Create: `PickleballKit/Sources/PickleballKit/GameConfiguration.swift`
- Create: `PickleballKit/Sources/PickleballKit/CoinFlip.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/CoreTypesTests.swift`

**Interfaces:**
- Consumes: nothing beyond the package scaffold from Task 1.
- Produces:
  - `Team: String, Codable, Sendable, CaseIterable { case teamA, teamB }`
    with `var opponent: Team`.
  - `ServerNumber: Int, Codable, Sendable { case one = 1, two = 2 }`.
  - `PlayMode: String, Codable, Sendable { case singles, doubles }`.
  - `ScoringFormat: Codable, Sendable, Equatable { case sideOut; case rally(freeze: Bool) }`.
  - `WinningScore: Int, Codable, Sendable, CaseIterable { case eleven = 11, fifteen = 15, twentyOne = 21 }`
    with `var sideSwitchThreshold: Int`.
  - `MatchFormat: Int, Codable, Sendable, CaseIterable { case bestOfOne = 1, bestOfThree = 3, bestOfFive = 5 }`
    with `var gamesToWin: Int`.
  - `GameConfiguration: Codable, Sendable, Equatable` with fields
    `playMode`, `scoringFormat`, `winningScore`, `winByTwo`, `timeoutsPerTeam`
    and a defaulted memberwise `init`.
  - `CoinFlip.flip<G: RandomNumberGenerator>(using:) -> Team` and
    `CoinFlip.flip() -> Team`.
- All later tasks import these types directly (no namespacing needed; one
  module).

- [ ] **Step 1: Write failing tests for the computed/behavioral pieces**

Create `PickleballKit/Tests/PickleballKitTests/CoreTypesTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class CoreTypesTests: XCTestCase {
    func testTeamOpponent() {
        XCTAssertEqual(Team.teamA.opponent, .teamB)
        XCTAssertEqual(Team.teamB.opponent, .teamA)
    }

    func testSideSwitchThresholds() {
        XCTAssertEqual(WinningScore.eleven.sideSwitchThreshold, 6)
        XCTAssertEqual(WinningScore.fifteen.sideSwitchThreshold, 8)
        XCTAssertEqual(WinningScore.twentyOne.sideSwitchThreshold, 11)
    }

    func testGamesToWin() {
        XCTAssertEqual(MatchFormat.bestOfOne.gamesToWin, 1)
        XCTAssertEqual(MatchFormat.bestOfThree.gamesToWin, 2)
        XCTAssertEqual(MatchFormat.bestOfFive.gamesToWin, 3)
    }

    func testGameConfigurationDefaults() {
        let config = GameConfiguration()
        XCTAssertEqual(config.playMode, .doubles)
        XCTAssertEqual(config.scoringFormat, .sideOut)
        XCTAssertEqual(config.winningScore, .eleven)
        XCTAssertTrue(config.winByTwo)
        XCTAssertEqual(config.timeoutsPerTeam, 2)
    }

    func testCoinFlipIsDeterministicWithSeededGenerator() {
        // A generator that always returns the same raw value must always
        // produce the same team — verified against the real stdlib
        // behavior: Bool.random(using:) with a generator fixed at
        // UInt64.max evaluates to false, i.e. .teamB.
        struct FixedGenerator: RandomNumberGenerator {
            func next() -> UInt64 { UInt64.max }
        }
        var generator = FixedGenerator()
        let result = CoinFlip.flip(using: &generator)
        XCTAssertEqual(result, .teamB)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile (types don't exist yet)**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — compiler errors like "cannot find type 'Team' in scope".

- [ ] **Step 3: Implement the core types**

Create `PickleballKit/Sources/PickleballKit/Team.swift`:

```swift
public enum Team: String, Codable, Sendable, CaseIterable {
    case teamA
    case teamB

    public var opponent: Team {
        self == .teamA ? .teamB : .teamA
    }
}
```

Create `PickleballKit/Sources/PickleballKit/ServerNumber.swift`:

```swift
public enum ServerNumber: Int, Codable, Sendable {
    case one = 1
    case two = 2
}
```

Create `PickleballKit/Sources/PickleballKit/PlayMode.swift`:

```swift
public enum PlayMode: String, Codable, Sendable {
    case singles
    case doubles
}
```

Create `PickleballKit/Sources/PickleballKit/ScoringFormat.swift`:

```swift
public enum ScoringFormat: Codable, Sendable, Equatable {
    case sideOut
    case rally(freeze: Bool)
}
```

Create `PickleballKit/Sources/PickleballKit/WinningScore.swift`:

```swift
public enum WinningScore: Int, Codable, Sendable, CaseIterable {
    case eleven = 11
    case fifteen = 15
    case twentyOne = 21

    /// Teams switch ends the first time either team reaches this score.
    /// Formula: ceil(winningScore / 2), which yields the standard 6/8/11
    /// thresholds for games to 11/15/21.
    public var sideSwitchThreshold: Int {
        Int((Double(rawValue) / 2.0).rounded(.up))
    }
}
```

Create `PickleballKit/Sources/PickleballKit/MatchFormat.swift`:

```swift
public enum MatchFormat: Int, Codable, Sendable, CaseIterable {
    case bestOfOne = 1
    case bestOfThree = 3
    case bestOfFive = 5

    public var gamesToWin: Int {
        (rawValue / 2) + 1
    }
}
```

Create `PickleballKit/Sources/PickleballKit/GameConfiguration.swift`:

```swift
public struct GameConfiguration: Codable, Sendable, Equatable {
    public var playMode: PlayMode
    public var scoringFormat: ScoringFormat
    public var winningScore: WinningScore
    public var winByTwo: Bool
    public var timeoutsPerTeam: Int

    public init(
        playMode: PlayMode = .doubles,
        scoringFormat: ScoringFormat = .sideOut,
        winningScore: WinningScore = .eleven,
        winByTwo: Bool = true,
        timeoutsPerTeam: Int = 2
    ) {
        self.playMode = playMode
        self.scoringFormat = scoringFormat
        self.winningScore = winningScore
        self.winByTwo = winByTwo
        self.timeoutsPerTeam = timeoutsPerTeam
    }
}
```

Create `PickleballKit/Sources/PickleballKit/CoinFlip.swift`:

```swift
public enum CoinFlip {
    public static func flip<G: RandomNumberGenerator>(using generator: inout G) -> Team {
        Bool.random(using: &generator) ? .teamA : .teamB
    }

    public static func flip() -> Team {
        var generator = SystemRandomNumberGenerator()
        return flip(using: &generator)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all `CoreTypesTests` and the Task 1 smoke test pass.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add PickleballKit core types and configuration"
```

---

## Task 3: GameState

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/GameState.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/GameStateTests.swift`

**Interfaces:**
- Consumes: `Team`, `ServerNumber` (Task 2).
- Produces: `GameState: Codable, Sendable, Equatable` — a plain value type
  (no behavior) with fields `teamAScore: Int`, `teamBScore: Int`,
  `servingTeam: Team`, `serverNumber: ServerNumber`,
  `teamATimeoutsRemaining: Int`, `teamBTimeoutsRemaining: Int`,
  `hasSideSwitched: Bool`, `lastPointWonWhileServing: Bool`, a full
  memberwise `init`, and accessors `score(for: Team) -> Int` /
  `timeoutsRemaining(for: Team) -> Int`. `PickleballGame` (Task 4 onward)
  owns all mutation of this struct; `GameState` itself never mutates.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/GameStateTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class GameStateTests: XCTestCase {
    func testInitAndAccessors() {
        let state = GameState(
            teamAScore: 3,
            teamBScore: 5,
            servingTeam: .teamA,
            serverNumber: .two,
            teamATimeoutsRemaining: 2,
            teamBTimeoutsRemaining: 1,
            hasSideSwitched: false,
            lastPointWonWhileServing: true
        )
        XCTAssertEqual(state.score(for: .teamA), 3)
        XCTAssertEqual(state.score(for: .teamB), 5)
        XCTAssertEqual(state.timeoutsRemaining(for: .teamA), 2)
        XCTAssertEqual(state.timeoutsRemaining(for: .teamB), 1)
    }

    func testEquatable() {
        let a = GameState(
            teamAScore: 0, teamBScore: 0, servingTeam: .teamA,
            serverNumber: .two, teamATimeoutsRemaining: 2,
            teamBTimeoutsRemaining: 2, hasSideSwitched: false,
            lastPointWonWhileServing: true
        )
        var b = a
        XCTAssertEqual(a, b)
        b.teamAScore = 1
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — "cannot find type 'GameState' in scope".

- [ ] **Step 3: Implement GameState**

Create `PickleballKit/Sources/PickleballKit/GameState.swift`:

```swift
public struct GameState: Codable, Sendable, Equatable {
    public var teamAScore: Int
    public var teamBScore: Int
    public var servingTeam: Team
    public var serverNumber: ServerNumber
    public var teamATimeoutsRemaining: Int
    public var teamBTimeoutsRemaining: Int
    public var hasSideSwitched: Bool
    public var lastPointWonWhileServing: Bool

    public init(
        teamAScore: Int,
        teamBScore: Int,
        servingTeam: Team,
        serverNumber: ServerNumber,
        teamATimeoutsRemaining: Int,
        teamBTimeoutsRemaining: Int,
        hasSideSwitched: Bool,
        lastPointWonWhileServing: Bool
    ) {
        self.teamAScore = teamAScore
        self.teamBScore = teamBScore
        self.servingTeam = servingTeam
        self.serverNumber = serverNumber
        self.teamATimeoutsRemaining = teamATimeoutsRemaining
        self.teamBTimeoutsRemaining = teamBTimeoutsRemaining
        self.hasSideSwitched = hasSideSwitched
        self.lastPointWonWhileServing = lastPointWonWhileServing
    }

    public func score(for team: Team) -> Int {
        team == .teamA ? teamAScore : teamBScore
    }

    public func timeoutsRemaining(for team: Team) -> Int {
        team == .teamA ? teamATimeoutsRemaining : teamBTimeoutsRemaining
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add GameState value type"
```

---

## Task 4: PickleballGame — Init, Doubles Side-Out, Win Conditions

This is the task the Review Focus's first two items belong to — the
most important task in the plan.

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/PickleballGame.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballGameDoublesSideOutTests.swift`

**Interfaces:**
- Consumes: `Team`, `ServerNumber`, `PlayMode`, `ScoringFormat`,
  `WinningScore`, `GameConfiguration`, `GameState` (Tasks 2-3).
- Produces: `PickleballGame` (`@Observable`, `final class`) with:
  - `init(configuration: GameConfiguration, firstServingTeam: Team, proUnlocked: Bool = true, demoPointCap: Int? = nil)`
  - `public let configuration: GameConfiguration`
  - `public private(set) var state: GameState`
  - `public var isGameOver: Bool`
  - `public var gameWinner: Team?`
  - `public func recordPoint(for scoringTeam: Team)`
  - `private func recordSideOutPoint(for scoringTeam: Team)` (doubles branch
    only in this task; Task 5 adds the singles branch by modifying this
    method)
  - `private func addScore(to team: Team)`
  All of Tasks 5-9 add to or modify this same file/class — later tasks'
  "Modify" sections show the complete resulting method bodies.

- [ ] **Step 1: Write failing tests for init and doubles rotation**

Create `PickleballKit/Tests/PickleballKitTests/PickleballGameDoublesSideOutTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballGameDoublesSideOutTests: XCTestCase {
    func testNewDoublesGameStartsAtServerTwo() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.state.serverNumber, .two)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
    }

    func testServingTeamScoringKeepsServe() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamA)
        XCTAssertEqual(game.state.teamAScore, 1)
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.state.serverNumber, .two)
    }

    func testFirstGameServerTwoLosingRallyCausesFullSideOut() {
        // The very first server of a new game is Server 2, so losing their
        // first rally is a full side-out straight to the other team.
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamB)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.state.serverNumber, .one)
    }

    func testSecondServerLosingRallyCausesFullSideOut() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        // Team A wins a point as Server 2, then loses: Server 2 losing a
        // rally always fully sides out, regardless of whether it was the
        // game's very first service turn.
        game.recordPoint(for: .teamA)
        game.recordPoint(for: .teamB)
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.state.serverNumber, .one)
    }

    func testServerOneLosingRallyAdvancesToServerTwoWithoutChangingTeam() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamB) // side-out: teamB now serving, Server 1
        game.recordPoint(for: .teamA) // teamB's Server 1 loses the rally
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.state.serverNumber, .two)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
    }

    func testLongStreakOfConsecutivePointsNeverMisfiresRotation() {
        // Review Focus: many consecutive points to the same server must
        // never erroneously flip server/team.
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        for expectedScore in 1...10 {
            game.recordPoint(for: .teamA)
            XCTAssertEqual(game.state.teamAScore, expectedScore)
            XCTAssertEqual(game.state.servingTeam, .teamA)
            XCTAssertEqual(game.state.serverNumber, .two)
        }
    }

    func testGameEndsAtWinningScoreWithSufficientMargin() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...11 {
            game.recordPoint(for: .teamA)
        }
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }
}
```

Win-by-two's tight-margin arithmetic (e.g. not ending at 10-10, ending at
12-10) is Review Focus item 2, and it is deliberately tested in Task 6's
`testWinByTwoRequiresTwoPointMarginUnderRallyScoring` rather than here:
under side-out scoring, a receiving team never scores directly (it only
gains serve), so there is no way to hand-drive the engine to an arbitrary
close score like 10-10 through side-out rotation without the test itself
duplicating/guessing at rotation logic. Rally scoring increments the score
on every single `recordPoint` call with no such indirection, which is what
makes it the correct place to pin this arithmetic precisely. The test
above (reaching 11-0 through side-out) is sufficient to confirm win-by-two
composes correctly with side-out scoring specifically.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — "cannot find type 'PickleballGame' in scope".

- [ ] **Step 3: Implement PickleballGame (doubles side-out + win conditions)**

Create `PickleballKit/Sources/PickleballKit/PickleballGame.swift`:

```swift
import Observation

@Observable
public final class PickleballGame {
    public let configuration: GameConfiguration
    public private(set) var state: GameState
    public private(set) var proUnlocked: Bool
    public let demoPointCap: Int?

    private var history: [GameState] = []

    public init(
        configuration: GameConfiguration,
        firstServingTeam: Team,
        proUnlocked: Bool = true,
        demoPointCap: Int? = nil
    ) {
        self.configuration = configuration
        self.proUnlocked = proUnlocked
        self.demoPointCap = demoPointCap

        let startingServerNumber: ServerNumber = configuration.playMode == .doubles ? .two : .one
        self.state = GameState(
            teamAScore: 0,
            teamBScore: 0,
            servingTeam: firstServingTeam,
            serverNumber: startingServerNumber,
            teamATimeoutsRemaining: configuration.timeoutsPerTeam,
            teamBTimeoutsRemaining: configuration.timeoutsPerTeam,
            hasSideSwitched: false,
            lastPointWonWhileServing: true
        )
    }

    public var canUndo: Bool { !history.isEmpty }

    public var isGameOver: Bool { gameWinner != nil }

    public var gameWinner: Team? {
        let a = state.teamAScore
        let b = state.teamBScore
        let target = configuration.winningScore.rawValue
        guard max(a, b) >= target else { return nil }
        if configuration.winByTwo && abs(a - b) < 2 { return nil }
        let leader: Team = a > b ? .teamA : .teamB
        if case .rally(let freeze) = configuration.scoringFormat, freeze {
            guard state.lastPointWonWhileServing else { return nil }
        }
        return leader
    }

    public func recordPoint(for scoringTeam: Team) {
        guard !isGameOver else { return }
        history.append(state)

        switch configuration.scoringFormat {
        case .sideOut:
            recordSideOutPoint(for: scoringTeam)
        case .rally:
            break // implemented in Task 6
        }
    }

    private func recordSideOutPoint(for scoringTeam: Team) {
        if scoringTeam == state.servingTeam {
            addScore(to: scoringTeam)
            state.lastPointWonWhileServing = true
            return
        }
        // Side-out event (doubles): Server 1 losing advances to Server 2
        // without changing the serving team; Server 2 losing fully sides
        // out to the other team at Server 1.
        switch state.serverNumber {
        case .one:
            state.serverNumber = .two
        case .two:
            state.servingTeam = scoringTeam
            state.serverNumber = .one
        }
    }

    private func addScore(to team: Team) {
        if team == .teamA {
            state.teamAScore += 1
        } else {
            state.teamBScore += 1
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests in `PickleballGameDoublesSideOutTests` pass,
plus all earlier tasks' tests still pass.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add PickleballGame doubles side-out engine and win conditions"
```

---

## Task 5: PickleballGame — Singles Side-Out

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift` (the
  `recordSideOutPoint` method only)
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballGameSinglesTests.swift`

**Interfaces:**
- Consumes: `PickleballGame` from Task 4 (modifies one method; the public
  `init`/`recordPoint`/`state`/`isGameOver`/`gameWinner` contract is
  unchanged).
- Produces: singles side-out behavior — losing a rally while receiving
  always causes an immediate side-out with no Server 1/Server 2 rotation
  (singles has only one server per team, so there is no second-server
  phase to pass through).

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/PickleballGameSinglesTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballGameSinglesTests: XCTestCase {
    func testNewSinglesGameStartsAtServerOne() {
        let config = GameConfiguration(playMode: .singles)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        XCTAssertEqual(game.state.serverNumber, .one)
    }

    func testSinglesSideOutIsImmediateRegardlessOfServerNumber() {
        let config = GameConfiguration(playMode: .singles)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        game.recordPoint(for: .teamB) // immediate side-out, no Server 2 phase
        XCTAssertEqual(game.state.servingTeam, .teamB)
        XCTAssertEqual(game.state.serverNumber, .one)
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertEqual(game.state.teamBScore, 0)
    }

    func testSinglesServingTeamScoringKeepsServe() {
        let config = GameConfiguration(playMode: .singles)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        game.recordPoint(for: .teamA)
        game.recordPoint(for: .teamA)
        XCTAssertEqual(game.state.teamAScore, 2)
        XCTAssertEqual(game.state.servingTeam, .teamA)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — `testSinglesSideOutIsImmediateRegardlessOfServerNumber`
fails because the current `recordSideOutPoint` always runs the doubles
Server 1 → Server 2 branch.

- [ ] **Step 3: Modify `recordSideOutPoint` to branch on `playMode`**

In `PickleballKit/Sources/PickleballKit/PickleballGame.swift`, replace the
`recordSideOutPoint` method with:

```swift
    private func recordSideOutPoint(for scoringTeam: Team) {
        if scoringTeam == state.servingTeam {
            addScore(to: scoringTeam)
            state.lastPointWonWhileServing = true
            return
        }
        // Side-out event.
        guard configuration.playMode == .doubles else {
            // Singles has only one server per team — any lost rally while
            // receiving is an immediate side-out.
            state.servingTeam = scoringTeam
            state.serverNumber = .one
            return
        }
        // Doubles: Server 1 losing advances to Server 2 without changing
        // the serving team; Server 2 losing fully sides out.
        switch state.serverNumber {
        case .one:
            state.serverNumber = .two
        case .two:
            state.servingTeam = scoringTeam
            state.serverNumber = .one
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests, including Task 4's doubles tests (unaffected
since `playMode` defaults to `.doubles`).

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add singles side-out scoring"
```

---

## Task 6: PickleballGame — Rally Scoring + Freeze

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift` (the
  `recordPoint` method's `.rally` branch, plus a new `recordRallyPoint`
  method)
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballGameRallyTests.swift`

**Interfaces:**
- Consumes: `PickleballGame` from Tasks 4-5; `ScoringFormat.rally(freeze:)`
  from Task 2; `GameState.lastPointWonWhileServing` from Task 3 (already
  read by `gameWinner`'s freeze check, written here for the first time).
- Produces: rally-scoring behavior — every rally scores a point for its
  winner regardless of who served, and serve passes to whoever just won
  the rally. `gameWinner`'s existing freeze check (Task 4) becomes
  exercised: with `freeze: true`, a team can only win the game on a rally
  they were already serving for, not one where they just took over serve.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/PickleballGameRallyTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballGameRallyTests: XCTestCase {
    func testRallyPointAlwaysScoresAndPassesServeToWinner() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false))
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)

        game.recordPoint(for: .teamB) // teamB wins the rally despite receiving
        XCTAssertEqual(game.state.teamBScore, 1)
        XCTAssertEqual(game.state.servingTeam, .teamB)

        game.recordPoint(for: .teamB) // teamB wins again, now serving
        XCTAssertEqual(game.state.teamBScore, 2)
        XCTAssertEqual(game.state.servingTeam, .teamB)
    }

    func testWinByTwoRequiresTwoPointMarginUnderRallyScoring() {
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: false),
            winningScore: .eleven,
            winByTwo: true
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...10 { game.recordPoint(for: .teamA) }
        game.recordPoint(for: .teamB) // 10-1, teamA still well ahead
        for _ in 1...9 { game.recordPoint(for: .teamB) } // teamB climbs to 10
        XCTAssertEqual(game.state.teamAScore, 10)
        XCTAssertEqual(game.state.teamBScore, 10)
        XCTAssertFalse(game.isGameOver) // 10-10, margin 0

        game.recordPoint(for: .teamA) // 11-10, margin 1
        XCTAssertFalse(game.isGameOver)

        game.recordPoint(for: .teamA) // 12-10, margin 2
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }

    func testFreezePreventsWinningOnARallyThatJustTookOverServe() {
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: true),
            winningScore: .eleven,
            winByTwo: true
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...9 { game.recordPoint(for: .teamA) } // 9-0, teamA serving
        game.recordPoint(for: .teamB) // 9-1, teamB now serving (took over)
        for _ in 1...8 { game.recordPoint(for: .teamB) } // 9-9, teamB serving throughout

        // teamB now wins what would be an 11-9 qualifying margin while
        // ALREADY serving (has held serve since 9-1) -> this IS a
        // legitimate on-serve win, not blocked by freeze.
        game.recordPoint(for: .teamB) // 9-10
        game.recordPoint(for: .teamB) // 9-11, margin 2, teamB was already serving
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamB)
    }

    func testFreezeBlocksWinOnTheExactRallyServeChangesHands() {
        let config = GameConfiguration(
            scoringFormat: .rally(freeze: true),
            winningScore: .eleven,
            winByTwo: true
        )
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...10 { game.recordPoint(for: .teamA) } // 10-0, teamA serving throughout
        for _ in 1...9 { game.recordPoint(for: .teamB) }  // teamB takes over serve and climbs to 9: 10-9, teamB serving
        XCTAssertEqual(game.state.teamAScore, 10)
        XCTAssertEqual(game.state.teamBScore, 9)
        XCTAssertEqual(game.state.servingTeam, .teamB)

        // teamA takes over serve on this exact rally: 11-9, margin 2 —
        // qualifies on score alone, but must be blocked because serve just
        // changed hands on this very rally.
        game.recordPoint(for: .teamA)
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.gameWinner)
        XCTAssertEqual(game.state.servingTeam, .teamA) // serve still passes to the rally winner as normal

        // teamA wins again, now already serving: 12-9, margin 3 -> legitimate win.
        game.recordPoint(for: .teamA)
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.gameWinner, .teamA)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — rally points currently fall into the `case .rally: break`
no-op branch in `recordPoint`, so scores never change for `.rally` games.

- [ ] **Step 3: Implement rally scoring**

In `PickleballKit/Sources/PickleballKit/PickleballGame.swift`, update
`recordPoint` and add `recordRallyPoint`:

```swift
    public func recordPoint(for scoringTeam: Team) {
        guard !isGameOver else { return }
        history.append(state)

        let previousServingTeam = state.servingTeam

        switch configuration.scoringFormat {
        case .sideOut:
            recordSideOutPoint(for: scoringTeam)
        case .rally:
            recordRallyPoint(for: scoringTeam, previousServingTeam: previousServingTeam)
        }
    }

    private func recordRallyPoint(for scoringTeam: Team, previousServingTeam: Team) {
        addScore(to: scoringTeam)
        state.lastPointWonWhileServing = (scoringTeam == previousServingTeam)
        state.servingTeam = scoringTeam
        state.serverNumber = .one
    }
```

(`recordSideOutPoint` and `addScore` are unchanged from Tasks 4-5.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all rally tests plus all earlier tasks' tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add rally scoring with freeze rule"
```

---

## Task 7: PickleballGame — Timeouts + Side-Switch Alerts

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift` (add
  `requestTimeout` method and a `checkSideSwitch` call from `recordPoint`)
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballGameTimeoutsAndSideSwitchTests.swift`

**Interfaces:**
- Consumes: `PickleballGame` (Tasks 4-6); `GameState.timeoutsRemaining`/
  `hasSideSwitched` (Task 3); `WinningScore.sideSwitchThreshold` (Task 2).
- Produces: `public func requestTimeout(for team: Team) -> Bool` (returns
  `false` and does nothing if that team has none remaining); `state.hasSideSwitched`
  flips from `false` to `true` exactly once, the first time either team's
  score reaches `configuration.winningScore.sideSwitchThreshold`.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/PickleballGameTimeoutsAndSideSwitchTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballGameTimeoutsAndSideSwitchTests: XCTestCase {
    func testTimeoutIsGrantedAndDecrements() {
        let game = PickleballGame(configuration: GameConfiguration(timeoutsPerTeam: 2), firstServingTeam: .teamA)
        XCTAssertTrue(game.requestTimeout(for: .teamA))
        XCTAssertEqual(game.state.timeoutsRemaining(for: .teamA), 1)
    }

    func testTimeoutIsDeniedWhenNoneRemaining() {
        let game = PickleballGame(configuration: GameConfiguration(timeoutsPerTeam: 1), firstServingTeam: .teamA)
        XCTAssertTrue(game.requestTimeout(for: .teamA))
        XCTAssertFalse(game.requestTimeout(for: .teamA))
        XCTAssertEqual(game.state.timeoutsRemaining(for: .teamA), 0)
    }

    func testSideSwitchTriggersAtThresholdForGameToEleven() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        XCTAssertFalse(game.state.hasSideSwitched)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertFalse(game.state.hasSideSwitched) // 5 points, threshold is 6
        game.recordPoint(for: .teamA)
        XCTAssertTrue(game.state.hasSideSwitched) // 6 points, threshold reached
    }

    func testSideSwitchOnlyTriggersOnce() {
        let config = GameConfiguration(scoringFormat: .rally(freeze: false), winningScore: .eleven)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...6 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.state.hasSideSwitched)
        game.recordPoint(for: .teamB)
        XCTAssertTrue(game.state.hasSideSwitched) // still true, not reset
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — `requestTimeout` doesn't exist yet; `hasSideSwitched`
never flips because nothing calls a side-switch check.

- [ ] **Step 3: Implement timeouts and side-switch checking**

In `PickleballKit/Sources/PickleballKit/PickleballGame.swift`, add a
`requestTimeout` method and call `checkSideSwitch()` at the end of
`recordPoint`:

```swift
    public func recordPoint(for scoringTeam: Team) {
        guard !isGameOver else { return }
        history.append(state)

        let previousServingTeam = state.servingTeam

        switch configuration.scoringFormat {
        case .sideOut:
            recordSideOutPoint(for: scoringTeam)
        case .rally:
            recordRallyPoint(for: scoringTeam, previousServingTeam: previousServingTeam)
        }

        checkSideSwitch()
    }

    private func checkSideSwitch() {
        guard !state.hasSideSwitched else { return }
        let threshold = configuration.winningScore.sideSwitchThreshold
        if state.teamAScore >= threshold || state.teamBScore >= threshold {
            state.hasSideSwitched = true
        }
    }

    @discardableResult
    public func requestTimeout(for team: Team) -> Bool {
        let remaining = state.timeoutsRemaining(for: team)
        guard remaining > 0 else { return false }
        history.append(state)
        if team == .teamA {
            state.teamATimeoutsRemaining -= 1
        } else {
            state.teamBTimeoutsRemaining -= 1
        }
        return true
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add timeouts and side-switch alerts"
```

---

## Task 8: PickleballGame — Undo + Manual Score Correction

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift` (add
  `undo()` and `correctScore(team:to:)`)
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballGameUndoAndCorrectionTests.swift`

**Interfaces:**
- Consumes: `PickleballGame` (Tasks 4-7), its private `history` stack
  (already populated by every mutating call since Task 4).
- Produces: `public func undo()` (restores the previous `state` from
  `history`; no-op if `history` is empty) and
  `public func correctScore(team: Team, to newScore: Int)` (directly sets
  a team's score, pushes to history first so it's itself undo-able, and is
  **not** blocked by `isGameOver` — see Review Focus item 3).

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/PickleballGameUndoAndCorrectionTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballGameUndoAndCorrectionTests: XCTestCase {
    func testUndoRestoresPreviousScoreAndServer() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamB) // full side-out: teamB now serving
        XCTAssertEqual(game.state.servingTeam, .teamB)
        game.undo()
        XCTAssertEqual(game.state.servingTeam, .teamA)
        XCTAssertEqual(game.state.serverNumber, .two)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoWithEmptyHistoryIsNoOp() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoAfterMultiplePointsStepsBackOneAtATime() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.recordPoint(for: .teamA) // 1-0
        game.recordPoint(for: .teamA) // 2-0
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 1)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
    }

    func testCorrectScoreSetsScoreDirectly() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.correctScore(team: .teamA, to: 7)
        XCTAssertEqual(game.state.teamAScore, 7)
    }

    func testCorrectScoreIsUndoable() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA)
        game.correctScore(team: .teamA, to: 7)
        game.undo()
        XCTAssertEqual(game.state.teamAScore, 0)
    }

    func testCorrectScoreCanReverseACompletedGameBackToInProgress() {
        // Review Focus: disputes are often about the final point.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let game = PickleballGame(configuration: config, firstServingTeam: .teamA)
        for _ in 1...11 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isGameOver)

        game.correctScore(team: .teamA, to: 9) // the last two points were a mistake
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.gameWinner)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — `undo()` and `correctScore(team:to:)` don't exist yet.

- [ ] **Step 3: Implement undo and correctScore**

In `PickleballKit/Sources/PickleballKit/PickleballGame.swift`, add:

```swift
    public func undo() {
        guard let previous = history.popLast() else { return }
        state = previous
    }

    public func correctScore(team: Team, to newScore: Int) {
        history.append(state)
        if team == .teamA {
            state.teamAScore = newScore
        } else {
            state.teamBScore = newScore
        }
    }
```

Note that `correctScore` deliberately has no `guard !isGameOver` check —
`isGameOver`/`gameWinner` are computed from `state`, so lowering a score
below the winning threshold automatically un-ends the game with no extra
code required.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add undo and manual score correction"
```

---

## Task 9: PickleballGame — Demo Cap / Paywall

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/PickleballGame.swift` (add
  `isPaywalled` computed property, `unlockPro()`, and a guard in
  `recordPoint`)
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballGameDemoCapTests.swift`

**Interfaces:**
- Consumes: `PickleballGame` (Tasks 4-8); `proUnlocked`/`demoPointCap`
  (already stored since Task 4's `init`, unused until now).
- Produces: `public var isPaywalled: Bool` (computed — **not** stored, so
  it can never go stale after an `undo()`; see Review Focus item 4) and
  `public func unlockPro()`. `recordPoint` becomes a no-op once
  `isPaywalled` is true.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/PickleballGameDemoCapTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballGameDemoCapTests: XCTestCase {
    func testGameIsNotPaywalledWhenProUnlocked() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: true, demoPointCap: 5)
        for _ in 1...10 { game.recordPoint(for: .teamA) }
        XCTAssertFalse(game.isPaywalled)
        XCTAssertEqual(game.state.teamAScore, 10)
    }

    func testGameBlocksScoringPastTheCapWhenNotUnlocked() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isPaywalled)
        XCTAssertEqual(game.state.teamAScore, 5)

        game.recordPoint(for: .teamA) // blocked
        XCTAssertEqual(game.state.teamAScore, 5)
    }

    func testUnlockProRemovesThePaywallAndAllowsPlayToContinue() {
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isPaywalled)

        game.unlockPro()
        XCTAssertFalse(game.isPaywalled)
        game.recordPoint(for: .teamA)
        XCTAssertEqual(game.state.teamAScore, 6)
    }

    func testUndoingBelowTheCapUnblocksScoringWithoutPurchase() {
        // Review Focus: isPaywalled must never go stale after an undo.
        let game = PickleballGame(configuration: GameConfiguration(), firstServingTeam: .teamA, proUnlocked: false, demoPointCap: 5)
        for _ in 1...5 { game.recordPoint(for: .teamA) }
        XCTAssertTrue(game.isPaywalled)

        game.undo() // back to 4
        XCTAssertFalse(game.isPaywalled)
        XCTAssertEqual(game.state.teamAScore, 4)

        game.recordPoint(for: .teamA) // allowed again, back to 5
        XCTAssertEqual(game.state.teamAScore, 5)
        XCTAssertTrue(game.isPaywalled)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — `isPaywalled`/`unlockPro()` don't exist yet; scoring is
never blocked.

- [ ] **Step 3: Implement the demo cap as a computed property**

In `PickleballKit/Sources/PickleballKit/PickleballGame.swift`, add:

```swift
    public var isPaywalled: Bool {
        guard !proUnlocked, let cap = demoPointCap else { return false }
        return max(state.teamAScore, state.teamBScore) >= cap
    }

    public func unlockPro() {
        proUnlocked = true
    }
```

And update `recordPoint`'s guard clause:

```swift
    public func recordPoint(for scoringTeam: Team) {
        guard !isGameOver, !isPaywalled else { return }
        history.append(state)

        let previousServingTeam = state.servingTeam

        switch configuration.scoringFormat {
        case .sideOut:
            recordSideOutPoint(for: scoringTeam)
        case .rally:
            recordRallyPoint(for: scoringTeam, previousServingTeam: previousServingTeam)
        }

        checkSideSwitch()
    }
```

Because `isPaywalled` is computed directly from `state` and `proUnlocked`
on every access (never cached), `undo()` from Task 8 automatically keeps
it correct with no additional code.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add demo point-cap and Pro unlock gate"
```

---

## Task 10: PickleballMatch — Best-of-N + Cross-Game Undo

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/PickleballMatch.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/PickleballMatchTests.swift`

**Interfaces:**
- Consumes: `PickleballGame`, `GameConfiguration`, `MatchFormat`, `Team`
  (Tasks 2-9).
- Produces: `PickleballMatch` (`@Observable`, `final class`) with:
  - `init(configuration: GameConfiguration, matchFormat: MatchFormat, firstServingTeam: Team, proUnlocked: Bool = true, demoPointCap: Int? = nil)`
  - `public let configuration: GameConfiguration`
  - `public let matchFormat: MatchFormat`
  - `public private(set) var completedGames: [PickleballGame]`
  - `public private(set) var currentGame: PickleballGame`
  - `public private(set) var gamesWon: [Team: Int]`
  - `public var isMatchOver: Bool`
  - `public var matchWinner: Team?`
  - `public func recordPoint(for team: Team)`
  - `public func undo()`
  This is the top-level type the iOS/Watch apps (Phases 3/5) will hold
  directly.

- [ ] **Step 1: Write failing tests**

Create `PickleballKit/Tests/PickleballKitTests/PickleballMatchTests.swift`:

```swift
import XCTest
@testable import PickleballKit

final class PickleballMatchTests: XCTestCase {
    func testMatchStartsWithFreshGameAndZeroGamesWon() {
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA)
        XCTAssertEqual(match.gamesWon[.teamA], 0)
        XCTAssertEqual(match.gamesWon[.teamB], 0)
        XCTAssertFalse(match.isMatchOver)
    }

    func testWinningAGameAdvancesToANewGameWithWinnerServingFirst() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        XCTAssertEqual(match.gamesWon[.teamA], 1)
        XCTAssertEqual(match.completedGames.count, 1)
        XCTAssertFalse(match.isMatchOver) // best of 3 needs 2 games won
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
        XCTAssertEqual(match.currentGame.state.servingTeam, .teamA) // winner serves next game
    }

    func testWinningEnoughGamesEndsTheMatch() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA)
        for _ in 1...2 {
            for _ in 1...11 { match.recordPoint(for: .teamA) }
        }
        XCTAssertTrue(match.isMatchOver)
        XCTAssertEqual(match.matchWinner, .teamA)
        XCTAssertEqual(match.gamesWon[.teamA], 2)
    }

    func testRecordPointIsNoOpOnceMatchIsOver() {
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        XCTAssertTrue(match.isMatchOver)
        match.recordPoint(for: .teamB)
        XCTAssertEqual(match.currentGame.state.teamBScore, 0)
    }

    func testUndoWithinTheCurrentGameDelegatesToIt() {
        let match = PickleballMatch(configuration: GameConfiguration(), matchFormat: .bestOfThree, firstServingTeam: .teamA)
        match.recordPoint(for: .teamA)
        match.undo()
        XCTAssertEqual(match.currentGame.state.teamAScore, 0)
    }

    func testUndoAcrossACompletedGameBoundaryRestoresExactPriorState() {
        // Review Focus: must restore the exact prior game's score/server
        // state, not just decrement a counter and start a blank game.
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfThree, firstServingTeam: .teamA)
        for _ in 1...11 { match.recordPoint(for: .teamA) } // game 1 won by teamA, 11-0
        XCTAssertEqual(match.gamesWon[.teamA], 1)
        XCTAssertEqual(match.completedGames.count, 1)

        match.undo() // currentGame (game 2) has no history -> cross-boundary undo

        XCTAssertEqual(match.gamesWon[.teamA], 0)
        XCTAssertEqual(match.completedGames.count, 0)
        XCTAssertEqual(match.currentGame.state.teamAScore, 10) // game 1's second-to-last state
        XCTAssertFalse(match.currentGame.isGameOver)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "PickleballKit" && swift test`
Expected: FAIL — "cannot find type 'PickleballMatch' in scope".

- [ ] **Step 3: Implement PickleballMatch**

Create `PickleballKit/Sources/PickleballKit/PickleballMatch.swift`:

```swift
import Observation

@Observable
public final class PickleballMatch {
    public let configuration: GameConfiguration
    public let matchFormat: MatchFormat
    public private(set) var completedGames: [PickleballGame] = []
    public private(set) var currentGame: PickleballGame
    public private(set) var gamesWon: [Team: Int] = [.teamA: 0, .teamB: 0]

    public init(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        firstServingTeam: Team,
        proUnlocked: Bool = true,
        demoPointCap: Int? = nil
    ) {
        self.configuration = configuration
        self.matchFormat = matchFormat
        self.currentGame = PickleballGame(
            configuration: configuration,
            firstServingTeam: firstServingTeam,
            proUnlocked: proUnlocked,
            demoPointCap: demoPointCap
        )
    }

    public var isMatchOver: Bool {
        gamesWon[.teamA, default: 0] >= matchFormat.gamesToWin
            || gamesWon[.teamB, default: 0] >= matchFormat.gamesToWin
    }

    public var matchWinner: Team? {
        if gamesWon[.teamA, default: 0] >= matchFormat.gamesToWin { return .teamA }
        if gamesWon[.teamB, default: 0] >= matchFormat.gamesToWin { return .teamB }
        return nil
    }

    public func recordPoint(for team: Team) {
        guard !isMatchOver else { return }
        currentGame.recordPoint(for: team)

        guard let winner = currentGame.gameWinner else { return }
        gamesWon[winner, default: 0] += 1
        completedGames.append(currentGame)

        guard !isMatchOver else { return }

        currentGame = PickleballGame(
            configuration: configuration,
            firstServingTeam: winner,
            proUnlocked: currentGame.proUnlocked,
            demoPointCap: currentGame.demoPointCap
        )
    }

    public func undo() {
        if currentGame.canUndo {
            currentGame.undo()
            return
        }
        guard let previousGame = completedGames.popLast() else { return }
        if let winner = previousGame.gameWinner {
            gamesWon[winner, default: 1] -= 1
        }
        currentGame = previousGame
        currentGame.undo()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "PickleballKit" && swift test`
Expected: PASS — all tests in the package, every task from 1 through 10.

- [ ] **Step 5: Commit**

```bash
git add PickleballKit
git commit -m "feat: add PickleballMatch best-of-N wrapper with cross-game undo"
```

---

## Final Verification

- [ ] Run the full suite one more time from the package root:

Run: `cd "PickleballKit" && swift test`
Expected: PASS, all tests across all 10 tasks.

- [ ] Push the branch and confirm the GitHub Actions workflow from Task 1
  passes on the PR before merging to `main`.
