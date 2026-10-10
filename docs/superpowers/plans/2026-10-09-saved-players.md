# Saved Players Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace free-typed-only player names with an optional saved-player roster, so per-player stats become meaningful and the user can designate themselves ("Me") for real personal win/loss stats.

**Architecture:** One new SwiftData model (`SavedPlayer`), one additive optional relationship on the existing `TeamSide` model (populated only for matches created after this feature ships — no migration of history), all new CRUD/query logic added to the existing `MatchRepository` (never touching `ModelContext` directly from UI code, per this project's established rule), and UI changes layered on top of `MatchSetupView`, a new `ManagePlayersView`, `StatsSummaryView`, and `HomeView`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (local + CloudKit private-database sync for history, same as every existing history model), XCTest (`swift test` for PickleballKit, `xcodebuild test` for the app targets).

**Spec:** `docs/superpowers/specs/2026-10-09-saved-players-design.md`

## Global Constraints

- `TeamSide.players` is `nil` on every match recorded before this feature ships — no migration or backfill script. Code must treat `nil` as "no player data available," never crash or assume non-nil.
- No new type bypasses `MatchRepository` for persistence — UI code calls repository methods, never `ModelContext` directly (existing project rule, stated in `MatchRepository`'s own doc comment).
- Every SwiftData model property needs a default value (CloudKit compatibility requirement already followed by every existing model in this schema — `TeamSide`, `MatchRecord`, `GameRecord`, `PointEvent` all do this).
- Every button/text element a new XCUITest looks up by string needs an explicit `.accessibilityIdentifier` matching that exact string (established project rule, discovered the hard way in Phase 3 — plain SwiftUI `Button(String)` does not set its identifier to match its label).
- Unit tests for PickleballKit-layer code (`SavedPlayer`, `MatchRepository` additions) always construct `ModelContext(try PersistenceContainer.makeInMemoryContainer())` explicitly — never `.mainContext` (a real, previously-diagnosed SwiftData instability in this project's exact Xcode/iOS Simulator environment when many ephemeral in-memory containers are created within one hosted-app XCTest process; `PickleballKitTests` runs via bare `swift test`, which never exhibited this, but stay consistent with the convention regardless).
- `GameRecord`'s point log is always read via `orderedPoints`, never raw `.points` (existing Global Constraint, still applies — unrelated to this feature but touched-adjacent code must not regress it).

## Review Focus

- A doubles match where one player field is left blank (falls back to the other player alone, per `combinedName`'s existing logic) must not upsert a blank/empty-string `SavedPlayer`, and must not crash when building `TeamSide.players` with fewer than 2 entries for that side.
- Marking a second player "Me" in Manage Players must actually un-set the previous one — a user re-marking by mistake should never end up with two players simultaneously `isMe == true`.
- `StatsSummaryView`/`HomeView` must not crash or show garbage numbers when no `SavedPlayer` has `isMe == true` yet (the common case for every existing install until the user visits Manage Players at least once).
- A match where "Me" is scorekeeping for other people (neither `TeamSide.players` array contains the "Me" player) must simply not count toward personal stats — not throw, not crash, not silently attribute the match to the wrong side.
- Deleting a `SavedPlayer` that's referenced by past matches (via the `.nullify` delete rule) must leave those matches' `TeamSide.displayName` strings intact and queryable in History — only the `players` relationship array entry disappears, nothing else.

---

### Task 1: SavedPlayer model, schema registration, and MatchRepository CRUD

**Files:**
- Create: `PickleballKit/Sources/PickleballKit/Persistence/SavedPlayer.swift`
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/TeamSide.swift`
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/PersistenceContainer.swift`
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift` (new file)

**Interfaces:**
- Produces: `SavedPlayer` (public final class, `@Model`: `id: UUID`, `name: String`, `isMe: Bool`, `teamSides: [TeamSide]?`); `TeamSide.players: [SavedPlayer]?`; `MatchRepository.fetchAllSavedPlayers() throws -> [SavedPlayer]`; `MatchRepository.upsertSavedPlayer(name: String) throws -> SavedPlayer?` (returns `nil` for blank/whitespace-only input, never creates a blank-name record); `MatchRepository.deleteSavedPlayer(_ player: SavedPlayer) throws`; `MatchRepository.setMePlayer(_ player: SavedPlayer) throws` (clears `isMe` on whichever player previously held it, sets it on this one); `MatchRepository.renameSavedPlayer(_ player: SavedPlayer, to newName: String) throws` (no-op on blank input); `MatchRepository.fetchMePlayer() throws -> SavedPlayer?`; extends `MatchRepository.saveCompletedMatch(_:teamAName:teamBName:startedAt:completedAt:teamAPlayers:teamBPlayers:)` with two new parameters, each defaulting to `[]`, used to populate the newly-created `TeamSide.players`.

- [ ] **Step 1: Write the failing tests**

```swift
// PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift
import XCTest
import SwiftData
@testable import PickleballKit

final class SavedPlayerRepositoryTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try PersistenceContainer.makeInMemoryContainer())
    }

    func testUpsertSavedPlayerCreatesNewPlayerOnFirstUse() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let player = try repository.upsertSavedPlayer(name: "Delon")
        XCTAssertEqual(player?.name, "Delon")
        XCTAssertFalse(player?.isMe ?? true)

        let all = try repository.fetchAllSavedPlayers()
        XCTAssertEqual(all.count, 1)
    }

    func testUpsertSavedPlayerReusesExistingPlayerByExactTrimmedName() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let first = try repository.upsertSavedPlayer(name: "Delon")
        let second = try repository.upsertSavedPlayer(name: "  Delon  ")

        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(try repository.fetchAllSavedPlayers().count, 1)
    }

    func testUpsertSavedPlayerReturnsNilForBlankOrWhitespaceName() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        XCTAssertNil(try repository.upsertSavedPlayer(name: ""))
        XCTAssertNil(try repository.upsertSavedPlayer(name: "   "))
        XCTAssertEqual(try repository.fetchAllSavedPlayers().count, 0)
    }

    func testSetMePlayerClearsPreviousMeAndSetsNewOne() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let alice = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Alice"))
        let bob = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Bob"))
        try repository.setMePlayer(alice)
        XCTAssertEqual(try repository.fetchMePlayer()?.id, alice.id)

        try repository.setMePlayer(bob)
        let all = try repository.fetchAllSavedPlayers()
        XCTAssertEqual(all.filter(\.isMe).count, 1)
        XCTAssertEqual(try repository.fetchMePlayer()?.id, bob.id)
    }

    func testDeleteSavedPlayerNullifiesButDoesNotDeleteHistoricalMatch() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let delon = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        _ = try repository.saveCompletedMatch(
            match, teamAName: "Delon & Mike", teamBName: "Opponents", startedAt: Date(),
            teamAPlayers: [delon]
        )

        try repository.deleteSavedPlayer(delon)

        let history = try repository.fetchMatchHistory()
        XCTAssertEqual(history.count, 1)
        let teamA = history[0].teamSides?.first { $0.team == .teamA }
        XCTAssertEqual(teamA?.displayName, "Delon & Mike")
        XCTAssertEqual(teamA?.players?.count ?? 0, 0)
    }

    func testRenameSavedPlayerUpdatesNameAndIgnoresBlankInput() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)

        let mike = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Mike"))
        let mikeID = mike.id

        try repository.renameSavedPlayer(mike, to: "Mike S.")
        XCTAssertEqual(mike.name, "Mike S.")
        XCTAssertEqual(mike.id, mikeID, "Rename must not change identity")

        try repository.renameSavedPlayer(mike, to: "   ")
        XCTAssertEqual(mike.name, "Mike S.", "A blank rename must be a no-op, not clear the name")
    }

    func testSaveCompletedMatchWithNoPlayersLeavesTeamSidePlayersEmpty() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }

        let saved = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: Date())

        let teamA = saved.teamSides?.first { $0.team == .teamA }
        XCTAssertEqual(teamA?.players?.count ?? 0, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd PickleballKit && swift test --filter SavedPlayerRepositoryTests`
Expected: FAIL to compile — `SavedPlayer`, `upsertSavedPlayer`, `fetchAllSavedPlayers`, `setMePlayer`, `fetchMePlayer`, `deleteSavedPlayer`, and the new `saveCompletedMatch` parameters don't exist yet.

- [ ] **Step 3: Create `SavedPlayer.swift`**

```swift
// PickleballKit/Sources/PickleballKit/Persistence/SavedPlayer.swift
import SwiftData
import Foundation

/// A persistent player identity, independent of any single match's
/// free-typed display names. Exists purely as a setup-time convenience and
/// a stats-attribution anchor — it does not replace `TeamSide.displayName`,
/// which remains the source of truth for what a match's scoreboard shows.
@Model
public final class SavedPlayer {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Exactly one `SavedPlayer` should have this `true` at a time —
    /// enforced by `MatchRepository.setMePlayer`, not by the model itself.
    public var isMe: Bool = false

    /// Inverse side of `TeamSide.players` — every match side this player
    /// has been part of. Not used by any current query (stats scan forward
    /// from `MatchRecord` → `TeamSide` → `players`), but declared so the
    /// relationship is properly bidirectional, matching every other
    /// to-many relationship already in this schema.
    public var teamSides: [TeamSide]? = []

    public init(id: UUID = UUID(), name: String, isMe: Bool = false) {
        self.id = id
        self.name = name
        self.isMe = isMe
    }
}
```

- [ ] **Step 4: Add the `players` relationship to `TeamSide`**

Modify `PickleballKit/Sources/PickleballKit/Persistence/TeamSide.swift` — add the relationship property (after `displayName`, before `match`):

```swift
    @Relationship(deleteRule: .nullify, inverse: \SavedPlayer.teamSides)
    public var players: [SavedPlayer]? = nil
```

Full file after this change:

```swift
import SwiftData
import Foundation

@Model
public final class TeamSide {
    public var id: UUID = UUID()
    public var teamRawValue: String = Team.teamA.rawValue
    public var displayName: String = ""
    public var match: MatchRecord?

    /// Populated only for matches saved after the Saved Players feature
    /// shipped — `nil` on every match recorded before. `.nullify` (not
    /// `.cascade`): deleting a `SavedPlayer` must remove it from this
    /// array without touching the match it played in.
    @Relationship(deleteRule: .nullify, inverse: \SavedPlayer.teamSides)
    public var players: [SavedPlayer]? = nil

    public init(id: UUID = UUID(), team: Team, displayName: String) {
        self.id = id
        self.teamRawValue = team.rawValue
        self.displayName = displayName
    }

    public var team: Team {
        Team(rawValue: teamRawValue) ?? .teamA
    }
}
```

- [ ] **Step 5: Register `SavedPlayer` in `PersistenceContainer`'s schema**

Modify `PickleballKit/Sources/PickleballKit/Persistence/PersistenceContainer.swift` — add `SavedPlayer.self` to `historyModelTypes` (it syncs via CloudKit alongside match history, same as `TeamSide`/`MatchRecord`/`GameRecord`/`PointEvent` — a player identity is exactly the kind of data that should follow the user's other devices):

```swift
    private static let historyModelTypes: [any PersistentModel.Type] = [
        TeamSide.self, MatchRecord.self, GameRecord.self, PointEvent.self, SavedPlayer.self
    ]
```

- [ ] **Step 6: Add CRUD methods to `MatchRepository`**

Modify `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift` — add these methods (placed after `fetchMatchHistory()`, before `deleteAllMatchHistory()`):

```swift
    // MARK: Saved Players

    public func fetchAllSavedPlayers() throws -> [SavedPlayer] {
        try modelContext.fetch(FetchDescriptor<SavedPlayer>())
    }

    public func fetchMePlayer() throws -> SavedPlayer? {
        try fetchAllSavedPlayers().first { $0.isMe }
    }

    /// Finds-or-creates a `SavedPlayer` by exact, trimmed, case-sensitive
    /// name match. Returns `nil` for blank/whitespace-only input without
    /// creating anything — callers must never upsert an empty field.
    @discardableResult
    public func upsertSavedPlayer(name: String) throws -> SavedPlayer? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = try fetchAllSavedPlayers().first(where: { $0.name == trimmed }) {
            return existing
        }
        let player = SavedPlayer(name: trimmed)
        modelContext.insert(player)
        try modelContext.save()
        return player
    }

    public func deleteSavedPlayer(_ player: SavedPlayer) throws {
        modelContext.delete(player)
        try modelContext.save()
    }

    /// Renames a `SavedPlayer` in place. Safe to do at any time, including
    /// after the player has appeared in past matches — identity is the
    /// stable `id`, not `name`, so this never breaks historical stats
    /// attribution (see `personalRecord`, Task 5). Exists specifically so
    /// a name collision (e.g. two different people both saved as "Mike")
    /// can be disambiguated — e.g. renaming one to "Mike S." — without
    /// losing anything.
    public func renameSavedPlayer(_ player: SavedPlayer, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        player.name = trimmed
        try modelContext.save()
    }

    /// Clears `isMe` on whichever `SavedPlayer` currently holds it before
    /// setting it on this one, so the exactly-one-"Me" invariant always
    /// holds after this call. Only touches the one previous holder (not
    /// every saved player) — safe because this function is the only writer
    /// of `isMe`, so "at most one `true`" holds by induction.
    public func setMePlayer(_ player: SavedPlayer) throws {
        if let previousMe = try fetchMePlayer(), previousMe.id != player.id {
            previousMe.isMe = false
        }
        player.isMe = true
        try modelContext.save()
    }
```

- [ ] **Step 7: Extend `saveCompletedMatch` to accept and link players**

Modify the existing `saveCompletedMatch` signature and body in `MatchRepository.swift`:

```swift
    @discardableResult
    public func saveCompletedMatch(
        _ match: PickleballMatch,
        teamAName: String,
        teamBName: String,
        startedAt: Date,
        completedAt: Date = Date(),
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = []
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

        modelContext.insert(record)

        let teamASide = TeamSide(team: .teamA, displayName: teamAName)
        let teamBSide = TeamSide(team: .teamB, displayName: teamBName)
        teamASide.match = record
        teamBSide.match = record
        teamASide.players = teamAPlayers
        teamBSide.players = teamBPlayers
        record.teamSides = [teamASide, teamBSide]
        modelContext.insert(teamASide)
        modelContext.insert(teamBSide)
```

(The rest of the method — game/point derivation and the final `save()`/`clearInProgressSnapshot()` — is unchanged; only the signature and the two new `teamASide.players =` / `teamBSide.players =` lines are new.)

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd PickleballKit && swift test --filter SavedPlayerRepositoryTests`
Expected: PASS, all 7 tests.

- [ ] **Step 9: Run the full PickleballKit suite to confirm nothing regressed**

Run: `cd PickleballKit && swift test`
Expected: PASS, all tests (85+ from before this task, plus the 7 new ones).

- [ ] **Step 10: Commit**

```bash
git add PickleballKit/Sources/PickleballKit/Persistence/SavedPlayer.swift PickleballKit/Sources/PickleballKit/Persistence/TeamSide.swift PickleballKit/Sources/PickleballKit/Persistence/PersistenceContainer.swift PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift
git commit -m "feat: add SavedPlayer model and repository CRUD"
```

---

### Task 2: Suggestion ranking

**Files:**
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift`

**Interfaces:**
- Consumes: `SavedPlayer`, `MatchRecord`, `TeamSide.players` from Task 1.
- Produces: `MatchRepository.suggestedPlayers(matching query: String) throws -> [SavedPlayer]` — case-insensitive substring match against `query` (empty query matches everyone), sorted primarily by most recent match date (descending; a player with no matches yet sorts last), secondarily by total times played (descending).

- [ ] **Step 1: Write the failing test**

```swift
    func testSuggestedPlayersFiltersAndRanksByRecencyThenFrequency() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let alice = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Alice"))
        let abby = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Abby"))
        _ = try repository.upsertSavedPlayer(name: "Bob") // never played, should sort last and be excluded by the "Al" query

        func playMatch(players: [SavedPlayer], at date: Date) throws {
            let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
            for _ in 1...11 { match.recordPoint(for: .teamA) }
            _ = try repository.saveCompletedMatch(match, teamAName: "A", teamBName: "B", startedAt: date, completedAt: date, teamAPlayers: players)
        }

        // Abby: 2 matches, most recent is older than Alice's most recent.
        try playMatch(players: [abby], at: Date(timeIntervalSince1970: 1000))
        try playMatch(players: [abby], at: Date(timeIntervalSince1970: 2000))
        // Alice: 1 match, but more recent than either of Abby's.
        try playMatch(players: [alice], at: Date(timeIntervalSince1970: 3000))

        let results = try repository.suggestedPlayers(matching: "Al")
        XCTAssertEqual(results.map(\.name), ["Alice"]) // "Bob" and "Abby" don't contain "Al"

        let allMatchingA = try repository.suggestedPlayers(matching: "A")
        XCTAssertEqual(allMatchingA.map(\.name), ["Alice", "Abby"]) // Alice ranks first: more recent match
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd PickleballKit && swift test --filter testSuggestedPlayersFiltersAndRanksByRecencyThenFrequency`
Expected: FAIL to compile — `suggestedPlayers` doesn't exist yet.

- [ ] **Step 3: Implement `suggestedPlayers`**

Add to `MatchRepository.swift`, after the CRUD methods from Task 1:

```swift
    /// Suggestion chips for `MatchSetupView`'s name fields. Empty `query`
    /// returns everyone. Ranking is derived fresh from match history on
    /// every call, not cached — see this plan's Task 1 rationale against
    /// stored counters.
    public func suggestedPlayers(matching query: String) throws -> [SavedPlayer] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let players = try fetchAllSavedPlayers()
        let matches = try fetchMatchHistory()

        func stats(for player: SavedPlayer) -> (mostRecent: Date, timesPlayed: Int) {
            var mostRecent = Date.distantPast
            var count = 0
            for match in matches {
                let appeared = (match.teamSides ?? []).contains { side in
                    (side.players ?? []).contains { $0.id == player.id }
                }
                if appeared {
                    count += 1
                    if match.completedAt > mostRecent { mostRecent = match.completedAt }
                }
            }
            return (mostRecent, count)
        }

        let filtered = trimmedQuery.isEmpty
            ? players
            : players.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }

        return filtered.sorted { lhs, rhs in
            let lhsStats = stats(for: lhs)
            let rhsStats = stats(for: rhs)
            if lhsStats.mostRecent != rhsStats.mostRecent {
                return lhsStats.mostRecent > rhsStats.mostRecent
            }
            return lhsStats.timesPlayed > rhsStats.timesPlayed
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd PickleballKit && swift test --filter SavedPlayerRepositoryTests`
Expected: PASS, all 8 tests (7 from Task 1 + this one).

- [ ] **Step 5: Commit**

```bash
git add PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift
git commit -m "feat: add recency/frequency-ranked player suggestions"
```

---

### Task 3: MatchSetupView — suggestion chips and upsert-on-start

**Files:**
- Modify: `ServerTwo/Setup/MatchSetupView.swift`
- Modify: `ServerTwo/ActiveMatchController.swift`
- Test: `ServerTwoUITests/SavedPlayersUITests.swift` (new file)

**Interfaces:**
- Consumes: `MatchRepository.suggestedPlayers(matching:)`, `.upsertSavedPlayer(name:)` from Tasks 1–2.
- Produces: `ActiveMatchController.startNewMatch(configuration:matchFormat:firstServingTeam:teamAName:teamBName:teamAPlayers:teamBPlayers:)` — two new parameters, each defaulting to `[]`; `ActiveMatchController.finishMatch()` passes its remembered `teamAPlayers`/`teamBPlayers` through to `repository.saveCompletedMatch`.

This task deliberately does **not** track "which player a chip-tap selected" as separate per-field state. Tapping a chip only autofills the text field with that player's exact canonical name string; identity resolution happens once, uniformly, at "Start Match" time via `upsertSavedPlayer(name:)` for every non-blank field — which transparently reuses the existing player when the text matches a chip-selected name exactly, and creates a new one otherwise. This keeps the UI layer simple: one code path handles both typed and chip-selected names.

- [ ] **Step 1: Write the failing test**

```swift
// ServerTwoUITests/SavedPlayersUITests.swift
import XCTest

final class SavedPlayersUITests: XCTestCase {
    func testPlayingAMatchSavesPlayerNamesAsSuggestionsForTheNextMatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState", "-UITest-DemoMatchLimit", "2"]
        app.launch()

        dismissOnboardingIfPresented(app)
        app.tabBars.buttons["Play"].tap()

        // First match: type a fresh name, nothing to suggest yet.
        let flipCoinButton = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton, in: app)
        let teamAField = app.textFields["Player Name"].firstMatch
        scrollUntilVisible(teamAField, in: app)
        app.swipeUp() // ensure doubles/singles toggle and name fields are in view together
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }

        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        teamATextField.tap()
        teamATextField.typeText("Delon")

        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText("Mike")

        flipCoinButton.tap()
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()

        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        // Second match: typing "Del" should surface a "Delon" suggestion chip.
        app.tabBars.buttons["Play"].tap()
        let teamATextField2 = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField2, in: app)
        teamATextField2.tap()
        teamATextField2.typeText("Del")

        let suggestionChip = app.buttons["PlayerSuggestion.Delon"]
        XCTAssertTrue(suggestionChip.waitForExistence(timeout: 2), "Delon should be suggested after playing a match with that name")
        suggestionChip.tap()
        XCTAssertEqual(teamATextField2.value as? String, "Delon")
    }

    func testLongPressingASuggestionChipOffersRemove() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)
        app.tabBars.buttons["Play"].tap()

        // Seed one saved player by playing a match named "Miek" (the typo
        // this gesture exists to let someone correct without visiting
        // Settings).
        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }
        teamATextField.tap()
        teamATextField.typeText("Miek")
        let flipCoinButton = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton, in: app)
        flipCoinButton.tap()
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()
        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["Play"].tap()
        let teamATextField2 = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField2, in: app)
        teamATextField2.tap()
        teamATextField2.typeText("Mie")

        let chip = app.buttons["PlayerSuggestion.Miek"]
        XCTAssertTrue(chip.waitForExistence(timeout: 2))
        chip.press(forDuration: 1.0)
        let removeMenuItem = app.buttons["Remove"]
        XCTAssertTrue(removeMenuItem.waitForExistence(timeout: 2), "Long-pressing a suggestion chip should offer Remove")
        removeMenuItem.tap()

        XCTAssertFalse(app.buttons["PlayerSuggestion.Miek"].waitForExistence(timeout: 2), "Removed player should no longer appear as a suggestion")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ServerTwo -destination 'id=<simulator-id>' -only-testing:ServerTwoUITests/SavedPlayersUITests`
Expected: FAIL — `Team A Player Name` identifier and `PlayerSuggestion.*` chips don't exist yet.

- [ ] **Step 3: Extend `ActiveMatchController`**

Modify `ServerTwo/ActiveMatchController.swift`:

```swift
    private(set) var match: PickleballMatch?
    private(set) var teamAName: String = "Team A"
    private(set) var teamBName: String = "Team B"
    private var startedAt: Date?
    private var teamAPlayers: [SavedPlayer] = []
    private var teamBPlayers: [SavedPlayer] = []
```

```swift
    func startNewMatch(
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        firstServingTeam: Team,
        teamAName: String,
        teamBName: String,
        teamAPlayers: [SavedPlayer] = [],
        teamBPlayers: [SavedPlayer] = []
    ) {
        self.teamAName = teamAName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team A" : teamAName
        self.teamBName = teamBName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Team B" : teamBName
        self.teamAPlayers = teamAPlayers
        self.teamBPlayers = teamBPlayers
        userDefaults.set(self.teamAName, forKey: Keys.activeTeamAName)
        userDefaults.set(self.teamBName, forKey: Keys.activeTeamBName)

        match = PickleballMatch(
            configuration: configuration,
            matchFormat: matchFormat,
            firstServingTeam: firstServingTeam,
            proUnlocked: proUnlocked,
            demoPointCap: nil
        )
        startedAt = Date()
        persistSnapshot()
    }
```

```swift
    @discardableResult
    func finishMatch() throws -> MatchRecord {
        guard let match, let startedAt else {
            throw ActiveMatchControllerError.noActiveMatch
        }
        let record = try repository.saveCompletedMatch(
            match,
            teamAName: teamAName,
            teamBName: teamBName,
            startedAt: startedAt,
            teamAPlayers: teamAPlayers,
            teamBPlayers: teamBPlayers
        )
        self.match = nil
        self.startedAt = nil
        self.teamAPlayers = []
        self.teamBPlayers = []
        userDefaults.removeObject(forKey: Keys.activeTeamAName)
        userDefaults.removeObject(forKey: Keys.activeTeamBName)
        return record
    }
```

Note: `teamAPlayers`/`teamBPlayers` are intentionally transient, in-memory-only state — not persisted to `UserDefaults` or the in-progress snapshot. If the app is killed and relaunched mid-match, `resumeIfNeeded()` restores the score/names as it already does, but these two arrays reset to empty; that resumed match will finish with `TeamSide.players` empty, same as any pre-feature match. This is a deliberate, bounded simplification — crash-recovery is rare, and losing fine-grained player attribution for that one match is an acceptable cost against the complexity of persisting and resolving player IDs through the snapshot/resume path.

- [ ] **Step 4: Add suggestion chips and upsert logic to `MatchSetupView`**

Modify `ServerTwo/Setup/MatchSetupView.swift`. First, give the existing name fields stable identifiers and add chip rows. Replace the "Team A" and "Team B" sections:

```swift
            Section("Team A") {
                TextField(playMode == .doubles ? "Player 1" : "Player Name", text: $teamAPlayer1)
                    .accessibilityIdentifier("Team A Player Name")
                suggestionChips(for: $teamAPlayer1, excluding: [])
                if playMode == .doubles {
                    TextField("Player 2", text: $teamAPlayer2)
                        .accessibilityIdentifier("Team A Player 2 Name")
                    suggestionChips(for: $teamAPlayer2, excluding: [])
                }
            }

            Section("Team B") {
                TextField(playMode == .doubles ? "Player 1" : "Player Name", text: $teamBPlayer1)
                    .accessibilityIdentifier("Team B Player Name")
                suggestionChips(for: $teamBPlayer1, excluding: [])
                if playMode == .doubles {
                    TextField("Player 2", text: $teamBPlayer2)
                        .accessibilityIdentifier("Team B Player 2 Name")
                    suggestionChips(for: $teamBPlayer2, excluding: [])
                }
            }
```

Add new state, the chip view, and a repository handle near the top of the struct:

```swift
    @Environment(\.modelContext) private var modelContext
    @State private var suggestions: [String: [SavedPlayer]] = [:] // keyed by the field's current text
```

Add this helper method (place near `combinedName`):

```swift
    @ViewBuilder
    private func suggestionChips(for field: Binding<String>, excluding: [String]) -> some View {
        let query = field.wrappedValue
        if !query.isEmpty {
            let repository = MatchRepository(modelContext: modelContext)
            let matches = (try? repository.suggestedPlayers(matching: query)) ?? []
            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(matches, id: \.id) { player in
                            Button(player.name) {
                                field.wrappedValue = player.name
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("PlayerSuggestion.\(player.name)")
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    try? repository.deleteSavedPlayer(player)
                                }
                            }
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    try? repository.deleteSavedPlayer(player)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
```

(`.swipeActions` has no effect on a bare `Button` outside a `List` row — the `.contextMenu` long-press is the functional quick-remove gesture for this layout; `.swipeActions` is left in place only if a later task moves chips into a `List`-backed row. For this task, long-press-to-remove via `.contextMenu` is the one that actually works and is what gets tested.)

Update `startMatch()` to upsert every non-blank field and pass the resulting players through:

```swift
    private func startMatch() {
        guard let firstServingTeam = coinFlipResult else { return }
        let scoringFormat: ScoringFormat = scoringFormatKind == .sideOut ? .sideOut : .rally(freeze: rallyFreeze)
        let configuration = GameConfiguration(
            playMode: playMode,
            scoringFormat: scoringFormat,
            winningScore: winningScore,
            winByTwo: winByTwo
        )
        let repository = MatchRepository(modelContext: modelContext)
        func upsertedPlayers(_ names: String...) -> [SavedPlayer] {
            names.compactMap { try? repository.upsertSavedPlayer(name: $0) }.compactMap { $0 }
        }
        let teamAPlayers = playMode == .doubles
            ? upsertedPlayers(teamAPlayer1, teamAPlayer2)
            : upsertedPlayers(teamAPlayer1)
        let teamBPlayers = playMode == .doubles
            ? upsertedPlayers(teamBPlayer1, teamBPlayer2)
            : upsertedPlayers(teamBPlayer1)
        activeMatchController.startNewMatch(
            configuration: configuration,
            matchFormat: matchFormat,
            firstServingTeam: firstServingTeam,
            teamAName: combinedName(teamAPlayer1, teamAPlayer2),
            teamBName: combinedName(teamBPlayer1, teamBPlayer2),
            teamAPlayers: teamAPlayers,
            teamBPlayers: teamBPlayers
        )
    }
```

(`upsertSavedPlayer(name:)` already returns `nil` and does nothing for a blank string, so passing a blank `teamAPlayer2` in singles/skipped-field cases is safe — `compactMap` drops it.)

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme ServerTwo -destination 'id=<simulator-id>' -only-testing:ServerTwoUITests/SavedPlayersUITests`
Expected: PASS.

- [ ] **Step 6: Run the full app test suite to confirm nothing regressed**

Run: `xcodebuild test -scheme ServerTwo -destination 'id=<simulator-id>'`
Expected: PASS, every existing test plus this new one. Pay particular attention to `GoldenPathUITests` and `PaywallTriggerUITests`, since both drive `MatchSetupView`'s name fields — the new `.accessibilityIdentifier`s on the text fields are additive, but confirm no existing lookup (e.g., by placeholder text) broke.

- [ ] **Step 7: Commit**

```bash
git add ServerTwo/Setup/MatchSetupView.swift ServerTwo/ActiveMatchController.swift ServerTwoUITests/SavedPlayersUITests.swift
git commit -m "feat: add player suggestion chips and upsert-on-start to MatchSetupView"
```

---

### Task 4: Settings — "Manage Players"

**Files:**
- Create: `ServerTwo/Players/ManagePlayersView.swift`
- Modify: `ServerTwo/Settings/SettingsView.swift`
- Test: `ServerTwoUITests/SavedPlayersUITests.swift`

**Interfaces:**
- Consumes: `MatchRepository.fetchAllSavedPlayers()`, `.setMePlayer(_:)`, `.deleteSavedPlayer(_:)`, `.renameSavedPlayer(_:to:)` from Task 1.
- Produces: `ManagePlayersView` (no init parameters beyond the implicit `modelContext` environment), reachable via a new `NavigationLink` in `SettingsView`.

- [ ] **Step 1: Write the failing test**

```swift
    func testMarkingAPlayerAsMeInManagePlayersEnforcesExactlyOne() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Create two players via a match, then go manage them.
        app.tabBars.buttons["Play"].tap()
        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }
        teamATextField.tap()
        teamATextField.typeText("Alice")
        let teamBTextField = app.textFields.matching(identifier: "Team B Player Name").firstMatch
        teamBTextField.tap()
        teamBTextField.typeText("Bob")
        let flipCoinButton = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton, in: app)
        flipCoinButton.tap()
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()
        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()

        let aliceMeButton = app.buttons["SetMe.Alice"]
        XCTAssertTrue(aliceMeButton.waitForExistence(timeout: 2))
        aliceMeButton.tap()
        XCTAssertTrue(app.staticTexts["Me.Alice"].waitForExistence(timeout: 2))

        let bobMeButton = app.buttons["SetMe.Bob"]
        bobMeButton.tap()
        XCTAssertTrue(app.staticTexts["Me.Bob"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Me.Alice"].exists, "Only one player should be marked Me at a time")
    }

    func testRenamingAPlayerInManagePlayersUpdatesTheDisplayedName() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }
        teamATextField.tap()
        teamATextField.typeText("Mike")
        let flipCoinButton = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton, in: app)
        flipCoinButton.tap()
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()
        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()

        app.buttons["Rename.Mike"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        // The field is pre-filled with the current name ("Mike") — delete it
        // before typing the replacement, since typeText only appends.
        let existingValue = nameField.value as? String ?? ""
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count))
        nameField.typeText("Mike S.")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["PlayerRow.Mike S."].waitForExistence(timeout: 2), "Renamed player should appear under the new name")
        XCTAssertFalse(app.staticTexts["PlayerRow.Mike"].exists, "Old name should no longer be listed")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ServerTwo -destination 'id=<simulator-id>' -only-testing:ServerTwoUITests/SavedPlayersUITests/testMarkingAPlayerAsMeInManagePlayersEnforcesExactlyOne`
Expected: FAIL — "Manage Players" link and `ManagePlayersView` don't exist yet.

- [ ] **Step 3: Create `ManagePlayersView`**

```swift
// ServerTwo/Players/ManagePlayersView.swift
import SwiftUI
import SwiftData
import PickleballKit

struct ManagePlayersView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var players: [SavedPlayer] = []
    @State private var loadError: Error?
    @State private var renamingPlayer: SavedPlayer?
    @State private var renameText: String = ""

    var body: some View {
        List {
            if players.isEmpty, loadError == nil {
                ContentUnavailableView(
                    "No Saved Players Yet",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Players you enter when starting a match are saved here automatically.")
                )
            } else {
                ForEach(players, id: \.id) { player in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(player.name)
                                .accessibilityIdentifier("PlayerRow.\(player.name)")
                            if player.isMe {
                                Text("Me")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("Me.\(player.name)")
                            }
                        }
                        Spacer()
                        Button("Rename") {
                            renameText = player.name
                            renamingPlayer = player
                        }
                        .accessibilityIdentifier("Rename.\(player.name)")
                        if !player.isMe {
                            Button("Set as Me") {
                                setMe(player)
                            }
                            .accessibilityIdentifier("SetMe.\(player.name)")
                        }
                    }
                }
                .onDelete(perform: deletePlayers)
            }
        }
        .navigationTitle("Manage Players")
        .task { loadPlayers() }
        .alert(
            "Rename Player",
            isPresented: Binding(
                get: { renamingPlayer != nil },
                set: { isPresented in if !isPresented { renamingPlayer = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let renamingPlayer {
                    rename(renamingPlayer, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func loadPlayers() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            players = try repository.fetchAllSavedPlayers().sorted { $0.name < $1.name }
            loadError = nil
        } catch {
            players = []
            loadError = error
        }
    }

    private func setMe(_ player: SavedPlayer) {
        let repository = MatchRepository(modelContext: modelContext)
        try? repository.setMePlayer(player)
        loadPlayers()
    }

    private func rename(_ player: SavedPlayer, to newName: String) {
        let repository = MatchRepository(modelContext: modelContext)
        try? repository.renameSavedPlayer(player, to: newName)
        loadPlayers()
    }

    private func deletePlayers(at offsets: IndexSet) {
        let repository = MatchRepository(modelContext: modelContext)
        for index in offsets {
            try? repository.deleteSavedPlayer(players[index])
        }
        loadPlayers()
    }
}

#Preview {
    NavigationStack {
        ManagePlayersView()
    }
    .modelContainer(try! PersistenceContainer.makeInMemoryContainer())
}
```

- [ ] **Step 4: Link it from `SettingsView`**

Modify `ServerTwo/Settings/SettingsView.swift`:

```swift
            Section("Help") {
                NavigationLink("How to Play Pickleball") {
                    HowToPlayView()
                }
                NavigationLink("Manage Players") {
                    ManagePlayersView()
                }
            }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme ServerTwo -destination 'id=<simulator-id>' -only-testing:ServerTwoUITests/SavedPlayersUITests`
Expected: PASS, all 4 tests in this file (2 from Task 3 + the 2 added in this task).

- [ ] **Step 6: Commit**

```bash
git add ServerTwo/Players/ManagePlayersView.swift ServerTwo/Settings/SettingsView.swift ServerTwoUITests/SavedPlayersUITests.swift
git commit -m "feat: add Manage Players settings screen with rename support"
```

---

### Task 5: Personal stats in StatsSummaryView and HomeView

**Files:**
- Modify: `ServerTwo/History/StatsSummaryView.swift`
- Modify: `ServerTwo/Home/HomeView.swift`
- Modify: `PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift`
- Test: `PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift`
- Test: `ServerTwoUITests/SavedPlayersUITests.swift`

**Interfaces:**
- Consumes: `MatchRepository.fetchMePlayer()` from Task 1.
- Produces: `MatchRepository.personalRecord(for player: SavedPlayer, in matches: [MatchRecord]) -> (wins: Int, losses: Int, pointsFor: Int, pointsAgainst: Int)` — a pure function over already-fetched data (no new I/O), so `StatsSummaryView`/`HomeView` can call it directly with matches they already have in memory.

- [ ] **Step 1: Write the failing test**

```swift
    func testPersonalRecordCountsOnlyMatchesIncludingThePlayerOnEitherSide() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let me = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Delon"))

        // Match 1: "Delon" on team A, team A wins 11-7.
        let match1 = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...7 { match1.recordPoint(for: .teamB) }
        for _ in 1...11 { match1.recordPoint(for: .teamA) }
        _ = try repository.saveCompletedMatch(match1, teamAName: "Delon & Mike", teamBName: "Opponents", startedAt: Date(), teamAPlayers: [me])

        // Match 2: "Delon" on team B, team A wins (so Delon loses).
        let match2 = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match2.recordPoint(for: .teamA) }
        _ = try repository.saveCompletedMatch(match2, teamAName: "Opponents", teamBName: "Delon & Mike", startedAt: Date(), teamBPlayers: [me])

        // Match 3: Delon not involved at all (scorekeeping for others).
        let match3 = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match3.recordPoint(for: .teamA) }
        _ = try repository.saveCompletedMatch(match3, teamAName: "Strangers", teamBName: "Others", startedAt: Date())

        let allMatches = try repository.fetchMatchHistory()
        let record = repository.personalRecord(for: me, in: allMatches)

        XCTAssertEqual(record.wins, 1)
        XCTAssertEqual(record.losses, 1)
        XCTAssertEqual(record.pointsFor, 11 + 0) // match1: 11 (team A), match2: 0 (team B's final score)
        XCTAssertEqual(record.pointsAgainst, 7 + 11)
    }

    func testPersonalRecordSurvivesRenamingThePlayer() throws {
        let context = try makeInMemoryContext()
        let repository = MatchRepository(modelContext: context)
        let config = GameConfiguration(winningScore: .eleven, winByTwo: true)

        let mike = try XCTUnwrap(try repository.upsertSavedPlayer(name: "Mike"))
        let match = PickleballMatch(configuration: config, matchFormat: .bestOfOne, firstServingTeam: .teamA, proUnlocked: true, demoPointCap: nil)
        for _ in 1...11 { match.recordPoint(for: .teamA) }
        _ = try repository.saveCompletedMatch(match, teamAName: "Mike & Delon", teamBName: "Opponents", startedAt: Date(), teamAPlayers: [mike])

        try repository.renameSavedPlayer(mike, to: "Mike S.")

        let allMatches = try repository.fetchMatchHistory()
        let record = repository.personalRecord(for: mike, in: allMatches)
        XCTAssertEqual(record.wins, 1, "Renaming must not sever the relationship to past matches — identity is the stable id, not the name")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd PickleballKit && swift test --filter testPersonalRecordCountsOnlyMatchesIncludingThePlayerOnEitherSide`
Expected: FAIL to compile — `personalRecord(for:in:)` doesn't exist yet.

- [ ] **Step 3: Implement `personalRecord`**

Add to `MatchRepository.swift`, after `suggestedPlayers`:

```swift
    /// A pure computation over already-fetched match history — no I/O, so
    /// callers that already hold `[MatchRecord]` (e.g. a loaded History
    /// screen) can call this directly without a redundant fetch.
    public func personalRecord(
        for player: SavedPlayer,
        in matches: [MatchRecord]
    ) -> (wins: Int, losses: Int, pointsFor: Int, pointsAgainst: Int) {
        var wins = 0, losses = 0, pointsFor = 0, pointsAgainst = 0
        for match in matches {
            guard let mySide = (match.teamSides ?? []).first(where: { side in
                (side.players ?? []).contains { $0.id == player.id }
            }) else { continue }

            if mySide.team == match.winningTeam {
                wins += 1
            } else {
                losses += 1
            }

            let finalGame = (match.games ?? []).max(by: { $0.gameNumber < $1.gameNumber })
            if let finalGame {
                let myScore = mySide.team == .teamA ? finalGame.teamAFinalScore : finalGame.teamBFinalScore
                let theirScore = mySide.team == .teamA ? finalGame.teamBFinalScore : finalGame.teamAFinalScore
                pointsFor += myScore
                pointsAgainst += theirScore
            }
        }
        return (wins, losses, pointsFor, pointsAgainst)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd PickleballKit && swift test --filter SavedPlayerRepositoryTests`
Expected: PASS, all tests in this file (10 total across Tasks 1, 2, and this one).

- [ ] **Step 5: Update `StatsSummaryView`**

Replace the full file:

```swift
import SwiftUI
import PickleballKit

struct StatsSummaryView: View {
    let matches: [MatchRecord]
    let mePlayer: SavedPlayer?
    let repository: MatchRepository

    var body: some View {
        HStack {
            statColumn(title: "Matches", value: "\(matches.count)")
            if let mePlayer {
                let record = repository.personalRecord(for: mePlayer, in: matches)
                Divider()
                statColumn(title: "Your Record", value: "\(record.wins) - \(record.losses)")
                Divider()
                statColumn(title: "Points For/Against", value: "\(record.pointsFor) - \(record.pointsAgainst)")
            }
        }
        .padding(.vertical, 8)
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    StatsSummaryView(matches: [], mePlayer: nil, repository: MatchRepository(modelContext: ModelContext(try! PersistenceContainer.makeInMemoryContainer())))
}
```

Modify `ServerTwo/History/MatchHistoryListView.swift` (the one existing call site) to pass the two new parameters. Find the current `StatsSummaryView(matches: matches)` call and its surrounding `loadMatches()`, and update:

```swift
    @State private var mePlayer: SavedPlayer?
```

```swift
                StatsSummaryView(matches: matches, mePlayer: mePlayer, repository: MatchRepository(modelContext: modelContext))
```

In `loadMatches()`, also fetch the "Me" player:

```swift
    private func loadMatches() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            matches = try repository.fetchMatchHistory()
            mePlayer = try repository.fetchMePlayer()
            loadError = nil
        } catch {
            matches = []
            loadError = error
        }
    }
```

- [ ] **Step 6: Update `HomeView`'s "Matches Played" card**

Modify `ServerTwo/Home/HomeView.swift`. Add state and update `loadMatches()`:

```swift
    @State private var mePlayer: SavedPlayer?
```

```swift
    private func loadMatches() {
        let repository = MatchRepository(modelContext: modelContext)
        do {
            matches = try repository.fetchMatchHistory()
            mePlayer = try repository.fetchMePlayer()
            loadError = nil
        } catch {
            matches = []
            loadError = error
        }
    }
```

Replace `matchesPlayedCard`:

```swift
    private var matchesPlayedCard: some View {
        Group {
            if let mePlayer {
                let repository = MatchRepository(modelContext: modelContext)
                let record = repository.personalRecord(for: mePlayer, in: matches)
                HStack {
                    Text("Your Record")
                        .font(.subheadline)
                    Spacer()
                    Text("\(record.wins) - \(record.losses)")
                        .font(.headline)
                }
            } else {
                HStack {
                    Text("Matches Played")
                        .font(.subheadline)
                    Spacer()
                    Text("\(matches.count)")
                        .font(.headline)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
```

- [ ] **Step 7: Write and run a UI test for the Home personal-record display**

```swift
    func testHomeShowsPersonalRecordOnceMeIsSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest-ResetState"]
        app.launch()
        dismissOnboardingIfPresented(app)

        app.tabBars.buttons["Play"].tap()
        let teamATextField = app.textFields.matching(identifier: "Team A Player Name").firstMatch
        scrollUntilVisible(teamATextField, in: app)
        let singlesToggle = app.buttons["Singles"]
        if singlesToggle.exists { singlesToggle.tap() }
        teamATextField.tap()
        teamATextField.typeText("Delon")
        let flipCoinButton = app.buttons["Flip Coin"]
        scrollUntilVisible(flipCoinButton, in: app)
        flipCoinButton.tap()
        let startMatchButton = app.buttons["Start Match"]
        scrollUntilVisible(startMatchButton, in: app)
        startMatchButton.tap()
        let teamAZone = app.buttons["scoreZone.teamA"]
        XCTAssertTrue(teamAZone.waitForExistence(timeout: 2))
        let finishButton = app.buttons["Finish Match"]
        for _ in 0..<20 {
            if finishButton.exists { break }
            teamAZone.tap()
        }
        finishButton.tap()
        app.buttons["Confirm Finish"].firstMatch.tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Manage Players"].tap()
        app.buttons["SetMe.Delon"].tap()

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Your Record"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["1 - 0"].waitForExistence(timeout: 2))
    }
```

Run: `xcodebuild test -scheme ServerTwo -destination 'id=<simulator-id>' -only-testing:ServerTwoUITests/SavedPlayersUITests`
Expected: PASS, all 5 tests in this file (2 from Task 3 + 2 from Task 4 + the 1 added in this task).

- [ ] **Step 8: Run the full project test suite**

Run: `cd PickleballKit && swift test`
Expected: PASS, full suite.

Run: `xcodebuild test -scheme ServerTwo -destination 'id=<simulator-id>'`
Expected: PASS, full suite — this is the first full run exercising everything from Tasks 1–5 together.

- [ ] **Step 9: Commit**

```bash
git add ServerTwo/History/StatsSummaryView.swift ServerTwo/History/MatchHistoryListView.swift ServerTwo/Home/HomeView.swift PickleballKit/Sources/PickleballKit/Persistence/MatchRepository.swift PickleballKit/Tests/PickleballKitTests/SavedPlayerRepositoryTests.swift ServerTwoUITests/SavedPlayersUITests.swift
git commit -m "feat: add personal win/loss record to StatsSummaryView and HomeView"
```
