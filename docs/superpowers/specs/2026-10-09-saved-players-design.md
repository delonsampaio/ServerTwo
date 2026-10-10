# Saved Players — Design Spec

## 1. Problem

Today, every match's player/team names are free-typed fresh at setup and stored only as a display-name string on `TeamSide` (e.g., `"Delon & Mike"`). `StatsSummaryView` aggregates wins by the literal `.teamA`/`.teamB` position label across every match in history — which is statistically meaningless, since that label isn't a persistent identity. "Team A" in one match has no relationship to "Team A" in another; the app is averaging unrelated things together and presenting it as one number.

There is also no way to compute genuinely personal stats (your win/loss record, your win streak) at all, since nothing in the data model identifies which side, across different matches, is "you."

## 2. Goals

- Let the same real person's name represent one persistent identity across matches, so per-player stats become meaningful.
- Let the user designate themselves ("Me") so the app can compute real personal stats (win/loss record, points for/against; win streak is a stretch goal, see §8).
- Preserve the app's zero-friction, courtside-utility feel — this must stay optional, never a gate in front of starting a match.
- Fix `StatsSummaryView`'s currently-meaningless Team A/B aggregate, whether or not "Me" has been set yet.

## 3. Non-Goals

- No retroactive linking of matches recorded before this feature ships. Old matches only count toward personal stats if an old free-typed name happens to exactly match a new `SavedPlayer`'s name — no migration, no backfill script.
- No fixed "Team" pairing concept. Doubles partners rotate match to match in this sport; the roster stores individual players only.
- No merging/deduplication UI for near-duplicate names (e.g., "Mike" typed twice for two different real people). Known v1 limitation — see §8.
- No cloud sync of the player roster beyond what CloudKit already does for match history generally.

## 4. Data Model

One new SwiftData model, in `PickleballKit/Sources/PickleballKit/Persistence/`:

```swift
@Model
public final class SavedPlayer {
    public var id: UUID
    public var name: String   // trimmed, as displayed
    public var isMe: Bool     // exactly one SavedPlayer has this true at a time

    public init(id: UUID = UUID(), name: String, isMe: Bool = false) {
        self.id = id
        self.name = name
        self.isMe = isMe
    }
}
```

No frequency or last-played counters are stored on `SavedPlayer`. Both are derived at read time by scanning match history, so there's no cached counter that can drift from reality (e.g., if a match is ever deleted in a future phase). At this app's realistic scale (a single local user's match history — realistically dozens to low hundreds of matches), scanning on read is fast enough that this isn't a real performance concern.

**One additive, optional schema change** to the existing model, in `MatchRecord.swift`:

```swift
@Relationship(deleteRule: .nullify)
public var players: [SavedPlayer]? = nil
```

Added to `TeamSide`, not `MatchRecord` — each side of a match gets its own list of the `SavedPlayer`s who played on it (one for singles, two for doubles). This field is populated only for matches created after this feature ships; it stays `nil` on every match recorded before. Stats computation checks `teamSide.players?.contains(where: { $0.isMe })` for new matches — no string parsing needed going forward. Older, `nil`-players matches are simply excluded from personal-stat scanning, consistent with §3.

This was revised during design from an original "zero data-model changes, derive identity by splitting the display-name string" approach, after a second-opinion review (see §9) correctly identified that exact-string identity is fragile over time — a renamed player would silently sever their link to past matches, and two different real people sharing a typed name would incorrectly merge. The relational field avoids both problems for everything going forward, at the cost of one small, additive, backward-compatible schema field (existing rows get `nil`, nothing breaks).

## 5. MatchSetupView Changes

Each player name field keeps working exactly as it does today — free text entry, zero added friction for a one-off pickup game against someone not in the roster. Below each field, a row of suggestion chips appears once the user has typed at least one character: existing `SavedPlayer`s whose name contains what's been typed so far, sorted primarily by most recent match date (descending) and secondarily, as a tiebreaker, by total times played (descending) — both derived from match history at read time, not stored. Tapping a chip fills the field with that player and remembers their `id` for this match (so `TeamSide.players` can be populated with the real `SavedPlayer` relationship, not just a name string, when the match is saved).

Typing a name that doesn't match any existing chip and starting the match anyway is always allowed — on "Start Match," every non-blank name field actually used (chip-selected or freshly typed) is upserted into `SavedPlayer`, using the raw text the user entered, *before* `ActiveMatchController`'s existing "Team A"/"Team B" fallback substitution for blank fields: if a `SavedPlayer` with that exact trimmed name already exists, its `id` is reused; otherwise a new one is created automatically. A field left blank (including a doubles field skipped under `combinedName`'s existing single-player fallback) is never upserted — nothing is saved for it, and the literal fallback strings "Team A"/"Team B" never become `SavedPlayer` entries. No "save this player?" prompt — this is silent and automatic, matching the auto-save decision in §7.

Each suggestion chip supports a quick-remove gesture (swipe or long-press) that deletes that `SavedPlayer` directly from the chip, without navigating to Settings — needed so a typo'd auto-saved name (e.g., "Miek") can be corrected immediately rather than accumulating as permanent suggestion clutter.

No team slot defaults to or pre-fills the "Me" player. Both Team A and Team B's fields start blank exactly as today — this is required so the app works correctly when the user is scorekeeping a match they aren't playing in themselves (see §8, "hand-off" case).

## 6. Settings — "Manage Players"

A new screen, reachable from `SettingsView`, listing every `SavedPlayer` alphabetically. Each row shows the name, a way to mark that player as "Me" (selecting a new one automatically un-sets the previous "Me," enforcing the exactly-one constraint), and a delete (swipe) action for permanently removing a player — needed both for general cleanup and for the "ghosts of pickup games past" case (an ex-partner's name no longer worth seeing suggested).

Marking "Me" happens only here, explicitly — never inferred automatically from usage patterns, since there's no reliable signal for it.

## 7. Auto-Save and Suggestion Ranking

Every name used to start a match is automatically saved to the roster, with no explicit "save" step — chosen over requiring deliberate saves because this is a casual/pickup sports utility, not a roster-management tool; forcing a "create player" detour before a pickup game would cut against everything else this app has been built around. The risk of this (a roster that accumulates one-off strangers forever) is mitigated by sorting suggestions by recency + frequency rather than alphabetically or by insertion order: people actually played with regularly naturally rise to the top of the suggestion chips, and one-off names sink down without ever being in the way, even though they technically remain in storage until explicitly deleted via the chip's quick-remove gesture or the Manage Players screen.

## 8. Stats Computation and Edge Cases

**Home and History stats**, once "Me" exists: win/loss record and points for/against, computed by scanning `MatchRecord`s whose `teamSides` include a `players` array containing the "Me" `SavedPlayer`'s `id`. If no "Me" player has been set yet, these personal stats simply don't render — `StatsSummaryView`'s existing meaningless Team A/B aggregate is removed regardless (see §10), not conditionally kept as a fallback.

**Win streak** is a stretch goal, not required for this spec's first implementation — it needs the match list sorted by `completedAt` and a simple consecutive-win scan from the most recent match backward; cheap to add once the base personal-stats scan exists, but called out separately so it doesn't block the core feature.

**"Hand-off" case** (scorekeeping a match the user isn't playing in): handled naturally by the containment check in §4 — if neither `TeamSide.players` array contains "Me," the match simply doesn't contribute to personal stats. No special-case code needed beyond not pre-filling a "Me" default in Setup (§5).

**Duplicate names** ("two Mikes" — different real people who both get typed as "Mike"): once a `SavedPlayer` exists for one "Mike," the setup suggestion chip should be used to select the *existing* record rather than retyping the name fresh; doing so correctly attributes future matches to the right person via `id`. If a user instead retypes "Mike" as fresh text without selecting the chip, a second, distinct `SavedPlayer` named "Mike" is created — an accepted v1 limitation (§3), not actively prevented or merged.

**Renaming** "Me" (e.g., after marriage, or switching to a nickname): since identity is the `SavedPlayer`'s stable `id`, not its `name` string, renaming in Manage Players doesn't sever the relationship to any past match recorded under the old name — no separate alias-list field is needed.

## 9. Design Review

This design went through one round of external second-opinion review (Gemini) before being finalized. Adopted: the relational `players` field in place of string-splitting (§4), the chip-level quick-remove gesture (§5), and the "hand-off" edge case requirement (§5, §8). Explicitly not adopted: a `knownAliases` array on `SavedPlayer` (made unnecessary once identity is UUID-based, not name-based) and a full historical migration/backfill script (unneeded given §3's non-goal of retroactive linking — new matches get clean relational identity from day one, and nothing needs backfilling).

## 10. Changes to Existing Views

- **`StatsSummaryView`**: the "Team A / Team B Wins" and "Points For/Against" columns (aggregated by position label) are removed — they are actively misleading, independent of whether this feature ships. Replaced with personal win/loss record + points for/against when "Me" is set, or simply omitted (keeping just the match count) when it isn't.
- **`HomeView`**: the "Matches Played" card becomes a personal win/loss record once "Me" is set, falling back to the existing total-match-count behavior otherwise.
- **`MatchSetupView`**: suggestion chips under each name field, per §5.
- **`SettingsView`**: new "Manage Players" entry under the existing Help/settings sections.

## 11. Testing Strategy

- Unit tests for `SavedPlayer` upsert-on-match-start (new name creates a record; existing exact-match name reuses the `id`; name is trimmed before comparison).
- Unit tests for recency/frequency-derived suggestion ranking against a small fixture match history.
- Unit tests for personal stats computation: a match including "Me" on either side counts correctly for both singles and doubles; a match excluding "Me" (hand-off case) doesn't; a match with `players == nil` (pre-feature legacy data) is excluded even if a name happens to match.
- UI test: typing a name, selecting a suggestion chip, starting a match, and confirming the match is saved with the correct `SavedPlayer` relationship.
- UI test: marking a player "Me" in Manage Players and confirming personal stats appear on Home afterward.
