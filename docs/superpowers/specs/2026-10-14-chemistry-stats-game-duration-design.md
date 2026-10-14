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

- **Overall match duration** — `match.completedAt - match.startedAt`, formatted via `Duration.seconds(interval).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))`, except intervals under 60 seconds (a fast test match, or a real match scored unrealistically quickly) show "< 1 min" rather than "0 min". Shown once in the summary card alongside the existing `formatSummary` pill ("Singles • Best of 1"). Note this is the time between the match being created and "Confirm Finish" being tapped on the Finish Match sheet — it can run a couple of minutes longer than the sum of the individual games' durations below, since players may chat at the net before confirming. That's expected, not a bug.
- **Closest game label** — within a single match's games (a no-op for Best of 1, which has only one game — and for any match where every game has the identical score margin, where "closest" has no meaning), the game with the smallest `|teamAFinalScore - teamBFinalScore|` gets a "Closest Game" tag. Ties on margin break toward the game with the higher combined point total (e.g. a 15-13 game beats an 11-9 game at the same 2-point margin — it went deeper). This needs only final scores, which every saved match already has, so it works on history saved before this feature shipped too.
- **Longest game label** — the game with the longest duration gets a "Longest Game" tag. Unlike "closest," this needs the new per-game timestamp below, so it's only available for matches played after this feature ships. If a single game is both closest and longest, it gets both tags. Neither label compares across different matches — this is purely about one match's own games relative to each other.

### Data model change

`GameRecord` gains one new field, additive and optional, following the exact precedent set by `TeamSide.players` in the Saved Players feature (nil default, no migration, existing rows simply have no value):

```swift
public var completedAt: Date? = nil
```

(Explicit `= nil`, not just `Date?` — matches the house style already used by `TeamSide.players: [SavedPlayer]? = nil` and `SavedPlayer.photoData: Data? = nil`.)

### Where the timestamp comes from

Per the Context section above, the live engine (`PickleballGame`/`PickleballMatch`) stays wall-clock-agnostic — this field is populated the same way `MatchRecord.startedAt`/`completedAt` already are: by the caller, not the engine.

**Not via `.onChange`** — that's a SwiftUI View modifier and doesn't exist on `ActiveMatchController`, which is a plain `@Observable` class, not a View. `ActiveMatchController` doesn't need to "observe" anything regardless: it already owns the only three call sites that can change `match.completedGames.count` —

```swift
func recordPoint(for team: Team) {
    match?.recordPoint(for: team)
    persistSnapshot()
}

func undo() {
    match?.undo()
    persistSnapshot()
}

func correctScore(team: Team, to newScore: Int) {
    match?.correctScore(team: team, to: newScore)
    persistSnapshot()
}
```

— `ScoringView` always goes through these wrappers, never touches `match.recordPoint`/`.undo`/`.correctScore` directly. Each of the three can grow `completedGames` by one (a game-winning point) or shrink it by one (`PickleballMatch.undo()` has an explicit `currentGameIsCounted` branch that does `completedGames.removeLast()` — undoing a game-winning point is a real, already-supported path, not an edge case). A plain append-only array would desync from `completedGames` the first time a game-winning point gets undone: the premature timestamp stays attached to the wrong game once the real winning point is replayed later.

`ActiveMatchController` gains:

```swift
private(set) var gameCompletionDates: [Date?] = []
```

— `[Date?]`, not `[Date]`, because a crash-resumed match can have games that completed before this session even started (no real timestamp to give them, and no honest way to represent "unknown" in a bare `[Date]`). Synced to `completedGames.count` at the end of each of the three wrapper methods above, via one small helper:

```swift
private func syncGameCompletionDates() {
    guard let count = match?.completedGames.count else { return }
    if gameCompletionDates.count > count {
        gameCompletionDates.removeLast(gameCompletionDates.count - count)
    } else if gameCompletionDates.count < count {
        gameCompletionDates.append(contentsOf: Array(repeating: Date(), count: count - gameCompletionDates.count))
    }
}
```

Growing always appends `Date()` (a real completion happening right now, in this live session) and shrinking always removes from the end (undo) — this is correct specifically because it's only ever called once per wrapper method, so the count can only have moved by one. On a fresh match (`confirmFirstServe`), `gameCompletionDates` starts `[]`. On a **crash-resumed** match, it's pre-sized instead of reset: `Array(repeating: nil, count: match.completedGames.count)` — the games that completed before the crash correctly get `nil` (we don't know when they really finished), and `syncGameCompletionDates()` only ever appends real dates for games completed from that point forward.

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
    gameCompletionDates: [Date?] = []  // new
) throws -> MatchRecord
```

Inside the existing `for game in match.completedGames` loop, each `GameRecord`'s `completedAt` is set from `gameCompletionDates[safe: gameNumber - 1] ?? nil` (a bounds-safe subscript — `gameCompletionDates` and `completedGames` should always be the same length by construction, but a mismatch degrades to `nil` rather than crashing). The default `[]` keeps every other existing caller, including every current test that calls `saveCompletedMatch` without this parameter, compiling unchanged.

### Closest/longest computation

A pure, local computation inside `MatchDetailView` (no repository change needed — it only touches the `orderedGames` this view already loads):

```swift
private var closestGameID: GameRecord.ID? {
    // A Best-of-1 match, or a match where every game happened to have the
    // identical margin, has no meaningfully "closest" game — tagging
    // Game 1 of a solitary 11-0 as "Closest Game" would be actively
    // misleading, not just unhelpful.
    guard orderedGames.count > 1 else { return nil }
    let margins = Set(orderedGames.map { abs($0.teamAFinalScore - $0.teamBFinalScore) })
    guard margins.count > 1 else { return nil }

    return orderedGames.min { lhs, rhs in
        let lhsMargin = abs(lhs.teamAFinalScore - lhs.teamBFinalScore)
        let rhsMargin = abs(rhs.teamAFinalScore - rhs.teamBFinalScore)
        if lhsMargin != rhsMargin { return lhsMargin < rhsMargin }
        // Tie on margin: the game with more total points went deeper
        // (e.g. 15-13 over 11-9 at the same 2-point margin) and is the
        // more deserving "closest" game.
        let lhsTotal = lhs.teamAFinalScore + lhs.teamBFinalScore
        let rhsTotal = rhs.teamAFinalScore + rhs.teamBFinalScore
        return lhsTotal > rhsTotal
    }?.id
}

private var longestGameID: GameRecord.ID? {
    guard orderedGames.count > 1 else { return nil }
    // All-or-nothing: a match that crashed and resumed mid-way can have
    // only its later games timestamped (see "Where the timestamp comes
    // from" above — pre-crash games correctly get `nil`, not a fabricated
    // date). Measuring some games against a stale checkpoint would
    // produce a confidently wrong "Longest Game" tag, which is worse than
    // no tag — so this skips the whole match rather than guess.
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

`closestGameID` needs only final scores — already present on every saved match, old or new — so it works on history saved before this feature shipped. It's `nil` for a Best of 1 (nothing to compare) or a match where every game has the identical margin (nothing distinguishes a "closest" one). `longestGameID` is additionally `nil` whenever any game in the match lacks a `completedAt` — any match saved before this feature shipped, or a crash-resumed match whose earlier games predate the live timestamp capture. No tag ever appears on data that can't support it; there's no fallback estimate.

### Testing

- `MatchRepositoryTests` (or wherever `saveCompletedMatch` is currently tested): a new case confirming `gameCompletionDates` lands on the correct `GameRecord` by position, and that omitting the parameter (existing callers) still saves successfully with `completedAt == nil` on every game.
- A unit test on `ActiveMatchController` (or an integration-style test driving it through a real point sequence) confirming `gameCompletionDates` stays correctly sized after: recording a game-winning point, undoing that exact point, then replaying it for real — the final array must have exactly one date for that game, not two or zero.
- `closestGameID`/`longestGameID` unit or UI tests covering: a Best of 1 match (both `nil`); a Best of 3 where every game has the same margin (`closestGameID` `nil`, since there's nothing to distinguish); a tie on margin where one game has a higher total score (that game wins the tiebreak); a match seeded without `gameCompletionDates` — i.e. every `completedAt` is `nil` — showing `closestGameID` populated (it only needs scores) but `longestGameID` `nil` (simulating pre-feature history, and confirming the two labels are independently gated, not both-or-nothing).

## Non-goals

- No history-wide "longest match ever" aggregate (explicitly descoped — per-match only, per the earlier discussion).
- No backfill of `completedAt` for existing `GameRecord` rows — they simply never show closest/longest tags for games predating this change, same treatment as any other additive-optional field in this codebase.
- No change to `PickleballGame`/`PickleballMatch`'s public API at all — this feature touches only `ActiveMatchController` (ServerTwo target) and `MatchRepository`/`GameRecord` (PickleballKit), never the scoring engine itself.
