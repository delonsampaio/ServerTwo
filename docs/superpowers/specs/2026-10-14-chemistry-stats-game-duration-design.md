# Chemistry Stats & Game Duration Design

**Goal:** Add two small, read-only stat features to History/Player Detail: "with you / against you" chemistry stats relative to "Me," and per-match game duration with closest/longest game callouts.

**Why bundled:** Both are small, additive, and in the same spirit (surfacing stats the app already has the raw data for, or nearly has it). Neither depends on the other. They're specced together because splitting two sub-day features into separate spec/plan/review cycles would be pure overhead, not because they share any code.

## Context

This follows a backlog discussion where several Gemini-suggested features were evaluated against the actual codebase. Two corrections came out of that review that matter here:

- The app's "Voice Announcer" setting (`AppSettings.voiceAnnouncerEnabled`) is a stored toggle with no consumer anywhere in the codebase — no `AVSpeechSynthesizer`, no `AVFoundation` import. Neither feature in this spec touches it.
- `PickleballMatch`/`PickleballGame` (PickleballKit's live scoring engine) deliberately tracks no wall-clock time at all — see `ResumedMatch`'s doc comment: "the engine itself doesn't track wall-clock time, so the repository carries it alongside." `MatchRepository.saveCompletedMatch` receives `startedAt`/`completedAt` as plain `Date` parameters from its caller (`ActiveMatchController`), not from the engine. This spec's game-duration feature follows that same established boundary rather than teaching the engine about dates.

## Feature 1: Chemistry Stats ("With You" / "Against You")

### What it shows

On `PlayerDetailView`, when viewing a player who is **not** "Me" and a "Me" player **is** set, up to two new rows appear between the existing hero stats strip and the Recent Form row:

- **As Your Partner** — record (wins–losses) across every doubles match where this player and "Me" were on the same `TeamSide`. Omitted entirely if zero such matches exist.
- **As Your Opponent** — record across every match (singles or doubles, combined) where this player and "Me" were on opposing sides. Omitted entirely if zero such matches exist.

Both rows are independently optional — two players could have only ever partnered (never opposed each other) or vice versa, so neither row is guaranteed to appear just because the other does.

Viewing "Me"'s own profile, or any profile when no "Me" is set, shows neither row — unchanged from today's layout.

### Data flow

New `MatchRepository` function, following the existing `mySide`/`personalRecord` pattern exactly (same file, same private helper reused):

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

This reuses the existing private `mySide(for:in:)` helper unchanged (id-match-first, name-fallback) — no changes to that helper or to any other existing `MatchRepository` function.

### UI integration

`PlayerDetailView` currently has no awareness of "Me." Rather than threading a new `mePlayer` parameter through every call site that constructs it (`ManagePlayersView`, and its own "Matches" section's `NavigationLink`s don't recurse into itself, so only one call site exists today), `PlayerDetailView.loadRecord()` fetches "Me" itself via the already-public `MatchRepository.fetchMePlayer()` (the same method `SettingsView` already calls) and stores it in a new `@State private var mePlayer: SavedPlayer?`. A computed `showsChemistry: Bool` is `mePlayer != nil && mePlayer?.id != player.id`; the two new rows render only when `showsChemistry` and their respective optional is non-nil.

### Testing

`SavedPlayerRepositoryTests` gets new cases mirroring the existing `personalRecord`/`winStreak` test style:
- Partner-only history (two players always on the same side) → `asPartner` populated, `asOpponent` nil.
- Opponent-only history → inverse.
- Mixed history (partnered in some matches, opposed in others) → both populated, correctly split.
- No shared matches at all → both nil.
- A `PlayerDetailView` UI test (matching the existing `SavedPlayersUITests` conventions) confirming the rows appear/don't appear per the "Me" visibility rule.

## Feature 2: Game Duration & Closest/Longest Game

### What it shows

On `MatchDetailView`'s per-game card (`gameCard(_:)`), two additions:

- **Overall match duration** — `match.completedAt - match.startedAt`, formatted (e.g. "24 min"), shown once in the summary card alongside the existing `formatSummary` pill ("Singles • Best of 1").
- **Closest / Longest game labels** — within a single match's games (relevant for Best of 3/5; a no-op for Best of 1, which has only one game), the game with the smallest `|teamAFinalScore - teamBFinalScore|` gets a "Closest Game" tag, and the game with the longest duration gets a "Longest Game" tag. If a single game is both, it gets both tags. No comparison across different matches — this is purely about one match's own games relative to each other.

### Data model change

`GameRecord` gains one new field, additive and optional, following the exact precedent set by `TeamSide.players` in the Saved Players feature (nil default, no migration, existing rows simply have no value):

```swift
public var completedAt: Date?
```

### Where the timestamp comes from

Per the Context section above, the live engine (`PickleballGame`/`PickleballMatch`) stays wall-clock-agnostic — this field is populated the same way `MatchRecord.startedAt`/`completedAt` already are: by the caller, not the engine.

`ActiveMatchController` already must observe `match.completedGames.count` growing during live play (the same signal `ScoringView`'s existing `.onChange(of: ...completedGames.count)` reacts to, for its own "Game Over" alert). It gains a new `private(set) var gameCompletionDates: [Date] = []`, appending `Date()` each time it detects `completedGames.count` increased. This array is positional — `gameCompletionDates[i]` corresponds to `completedGames[i]` — matching how `MatchRepository.saveCompletedMatch` already iterates `match.completedGames` by index when building `GameRecord`s.

`MatchRepository.saveCompletedMatch` gains one new parameter:

```swift
public func saveCompletedMatch(
    _ match: PickleballMatch,
    teamAName: String,
    teamBName: String,
    startedAt: Date,
    completedAt: Date = Date(),
    teamAPlayers: [SavedPlayer] = [],
    teamBPlayers: [SavedPlayer] = [],
    gameCompletionDates: [Date] = []  // new
) throws -> MatchRecord
```

Inside the existing `for game in match.completedGames` loop, each `GameRecord`'s `completedAt` is set from `gameCompletionDates[safe: gameNumber - 1]` (a bounds-safe subscript, since a resumed-from-crash match's `gameCompletionDates` could be shorter than `completedGames` if the app relaunched mid-match — those earlier games simply get `nil`, same as any other historical row). The default `[]` keeps every other existing caller (including every current test that calls `saveCompletedMatch` without this parameter) compiling unchanged.

### Closest/longest computation

A pure, local computation inside `MatchDetailView` (no repository change needed — it only touches the `orderedGames` this view already loads):

```swift
private var closestGameID: GameRecord.ID? {
    orderedGames.min { abs($0.teamAFinalScore - $0.teamBFinalScore) < abs($1.teamAFinalScore - $1.teamBFinalScore) }?.id
}

private var longestGameID: GameRecord.ID? {
    // All-or-nothing: a match that crashed and resumed mid-way could have
    // only its later games timestamped (gameCompletionDates shorter than
    // completedGames at the moment it was saved — see "Where the
    // timestamp comes from" below). Measuring some games against a stale
    // checkpoint would produce a confidently wrong "Longest Game" tag,
    // which is worse than no tag — so this skips the whole match rather
    // than guess.
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

`closestGameID` is `nil` only when `orderedGames` is empty (never true for a saved match). `longestGameID` is additionally `nil` whenever any game in the match lacks a `completedAt` — a match with only one game, any match saved before this feature shipped, or a crash-resumed match whose earlier games predate the live timestamp capture. No tag ever appears on data that can't support it; there's no fallback estimate.

### Testing

- `MatchRepositoryTests` (or wherever `saveCompletedMatch` is currently tested): a new case confirming `gameCompletionDates` lands on the correct `GameRecord` by position, and that omitting the parameter (existing callers) still saves successfully with `completedAt == nil` on every game.
- A `MatchDetailView` UI test confirming the duration string and closest/longest tags render for a freshly-played Best of 3 match, and confirming no tags appear for a Best of 1 match (only one game, nothing to compare) or for a match seeded without `gameCompletionDates` (simulating pre-feature history).

## Non-goals

- No history-wide "longest match ever" aggregate (explicitly descoped — per-match only, per the earlier discussion).
- No backfill of `completedAt` for existing `GameRecord` rows — they simply never show closest/longest tags for games predating this change, same treatment as any other additive-optional field in this codebase.
- No change to `PickleballGame`/`PickleballMatch`'s public API beyond nothing — this feature touches only `ActiveMatchController` (ServerTwo target) and `MatchRepository`/`GameRecord` (PickleballKit), never the scoring engine itself.
