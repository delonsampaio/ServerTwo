import SwiftUI
import SwiftData
import Combine

extension Notification.Name {
    /// Posted after Edit Players saves. History, Home and a player's screen
    /// each load their matches once per view lifetime, so a plain pop back
    /// would otherwise leave their rows and stats stale until pull-to-refresh.
    static let matchPlayersEdited = Notification.Name("ServerTwo.matchPlayersEdited")
    /// Posted after a match is deleted, carrying its `persistentModelID` (see
    /// `MatchDeleted`). Open screens drop that match at once through
    /// `onMatchDeleted`, then reload on their next appearance like
    /// `matchPlayersEdited`.
    static let matchDeleted = Notification.Name("ServerTwo.matchDeleted")
    /// Posted after a match finished on the Watch was imported. Unlike the two
    /// above, screens reload IMMEDIATELY: nothing they show is being edited, and
    /// a new match should appear while the user is looking at History.
    static let matchSyncedFromWatch = Notification.Name("ServerTwo.matchSyncedFromWatch")
}

/// When a screen refreshes for each notification, as a pure decision so it is
/// unit tested without a view.
enum ScreenRefreshTiming: Equatable {
    /// Mark stale; reload at the next `onAppear` (a pushed Match Detail or the
    /// edit sheet that caused the change may still be on screen).
    case onNextAppear
    /// Reload right away.
    case immediately

    static func timing(for name: Notification.Name) -> ScreenRefreshTiming? {
        switch name {
        case .matchPlayersEdited, .matchDeleted: .onNextAppear
        case .matchSyncedFromWatch: .immediately
        default: nil
        }
    }
}

/// The payload of `.matchDeleted`. It is the deleted match's id and nothing
/// else on purpose: screens still hold the deleted `MatchRecord` objects, and
/// reading `teamSides`/`games` from one traps in SwiftData ("backing data could
/// no longer be found"), whereas reading an id is safe. Read the id BEFORE
/// deleting.
enum MatchDeleted {
    private static let idKey = "matchID"

    /// Every match deleted in this process. A row's content can still be
    /// evaluated with the deleted record AFTER the screen dropped it from its
    /// array (reproduced: Player detail on another tab, the row label ran again
    /// in the render pass that followed the delete). A `@State` copy of this set
    /// was NOT reliable there (the stale evaluation read an old, empty value),
    /// so rows ask this process-wide set instead, by id only, before reading
    /// anything else from their match. Ids are permanent and never reused.
    private(set) static var deletedIDs: Set<PersistentIdentifier> = []

    static func hasBeenDeleted(_ id: PersistentIdentifier) -> Bool {
        deletedIDs.contains(id)
    }

    static func post(matchID: PersistentIdentifier) {
        deletedIDs.insert(matchID)
        NotificationCenter.default.post(name: .matchDeleted, object: nil, userInfo: [idKey: matchID])
    }

    static func matchID(in notification: Notification) -> PersistentIdentifier? {
        notification.userInfo?[idKey] as? PersistentIdentifier
    }
}

extension Array where Element: PersistentModel {
    /// The array without the model with this id. Compares ids only, so it is
    /// safe on an array that still holds the deleted model.
    func removing(modelID: PersistentIdentifier) -> [Element] {
        filter { $0.persistentModelID != modelID }
    }
}

/// Reloads a screen's matches once, the next time it appears after an edit
/// (or after a match was deleted, `.matchDeleted`).
/// The notification only marks the screen stale; the reload waits for the
/// next `onAppear` so it never runs while a pushed Match Detail (or the
/// sheet) that belongs to this screen is still on screen.
///
/// It reloads and bumps `revision`, nothing else. SwiftData's change tracking
/// did not reliably re-render rows after Edit Players changed a side (verified
/// in a UI test: the models were updated, the rows kept the old names), so the
/// screen applies `.id(revision)` to its ROW content only. Never put it on the
/// List/ScrollView root: that would reset the scroll position and re-run the
/// screen's `.task`.
private struct RefreshAfterPlayersEdited: ViewModifier {
    @Binding var revision: Int
    let reload: @MainActor () -> Void
    @State private var isStale = false

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .matchPlayersEdited)
                    .merge(with: NotificationCenter.default.publisher(for: .matchDeleted))
                    .merge(with: NotificationCenter.default.publisher(for: .matchSyncedFromWatch))
            ) { notification in
                switch ScreenRefreshTiming.timing(for: notification.name) {
                case .immediately:
                    reload()
                    revision += 1
                case .onNextAppear:
                    isStale = true
                case nil:
                    break
                }
            }
            .onAppear {
                guard isStale else { return }
                isStale = false
                reload()
                revision += 1
            }
    }
}

extension View {
    /// Runs `action` with the id of every match deleted anywhere in the app,
    /// immediately (not on the next appear). A screen that keeps `MatchRecord`s
    /// in `@State` uses this to drop the deleted one before anything can read
    /// its properties; the normal reload on next appear still follows.
    func onMatchDeleted(perform action: @escaping @MainActor (PersistentIdentifier) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .matchDeleted)) { notification in
            guard let id = MatchDeleted.matchID(in: notification) else { return }
            action(id)
        }
    }

    func refreshAfterPlayersEdited(revision: Binding<Int>, reload: @escaping @MainActor () -> Void) -> some View {
        modifier(RefreshAfterPlayersEdited(revision: revision, reload: reload))
    }
}
