import Foundation

/// What happened to the standalone match, for anything that follows its
/// lifecycle without scoring it (the Watch's workout session). Emitted by
/// `StandaloneMatchSession.onLifecycleEvent` after the state change.
public enum MatchLifecycleEvent: Equatable, Sendable {
    /// A match began (after the coin flip).
    case started
    /// The deciding point was scored: the match is over but Undo still works.
    case decided
    /// Undo took the deciding point back: the match is live again.
    case reopened
    /// Done (or an abandon of an already saved match): the match is final and
    /// saved under this id.
    case finished(matchID: UUID)
    /// End Match on an unsaved match: nothing was kept.
    case abandoned
}
