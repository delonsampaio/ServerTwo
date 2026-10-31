import Foundation
import Observation
import os

/// The free-demo rule for the Watch, the same one the phone applies: ONE
/// completed match for life unless Pro. Pure so it is covered by `swift test`.
public enum WatchDemoGate {
    /// Same as `ActiveMatchController.demoMatchLimit`.
    public static let demoMatchLimit = 1

    /// The budget is shared with the phone, so the count is the LARGER of the
    /// two, not their sum: a match played on the Watch and already imported by
    /// the phone counts once. Checked when a match is about to start, never
    /// mid-match.
    public static func canStartMatch(isPro: Bool, localCount: Int, phoneCount: Int, limit: Int) -> Bool {
        isPro || max(localCount, phoneCount) < limit
    }
}

/// The Pro product and the rule for "does this list of entitlements unlock it",
/// shared by the phone's `StoreManager` and the Watch so they cannot disagree.
public struct ProEntitlementRecord: Sendable, Equatable {
    public let productID: String
    /// Non-nil once the purchase was refunded or a family-shared copy revoked.
    public let revocationDate: Date?

    public init(productID: String, revocationDate: Date?) {
        self.productID = productID
        self.revocationDate = revocationDate
    }
}

public enum ProEntitlementRule {
    /// Non-consumable, Family Sharing on.
    public static let productID = "com.delonsampaio.ServerTwo.pro"

    /// Any copy (bought or family-shared) counts and a revoked one never does,
    /// so a refund re-locks while a still-valid second copy keeps Pro.
    public static func isPro(from entitlements: [ProEntitlementRecord]) -> Bool {
        entitlements.contains { $0.productID == productID && $0.revocationDate == nil }
    }
}

/// How many matches this Watch has completed, for life. Persisted so the demo
/// cannot be reset by relaunching; `Sendable` through the defaults suite name,
/// with a process-wide lock around the read-modify-write (as `PendingSyncStore`).
public struct WatchLifetimeCounter: Sendable {
    public static let defaultsKey = "watchLifetimeCompletedMatchCount"
    private static let lock = OSAllocatedUnfairLock()

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var userDefaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public var count: Int {
        Self.lock.withLock { max(0, userDefaults.integer(forKey: Self.defaultsKey)) }
    }

    public func increment() {
        Self.lock.withLock {
            userDefaults.set(max(0, userDefaults.integer(forKey: Self.defaultsKey)) + 1, forKey: Self.defaultsKey)
        }
    }

    /// For an undone deciding point; never below zero.
    public func decrement() {
        Self.lock.withLock {
            userDefaults.set(max(0, userDefaults.integer(forKey: Self.defaultsKey) - 1), forKey: Self.defaultsKey)
        }
    }
}

/// What the iPhone tells the Watch (`updateApplicationContext`): whether Pro is
/// unlocked there, how many matches the phone counts toward the demo, and the
/// saved players the Watch can pick from. Plain property-list values only, as
/// WatchConnectivity requires.
public struct PhoneStateContext: Codable, Sendable, Equatable {
    public static let proUnlockedKey = "proUnlocked"
    public static let completedMatchCountKey = "completedMatchCount"
    public static let playersKey = "players"

    public let proUnlocked: Bool
    public let completedMatchCount: Int
    /// The phone's ordered player list. `nil` means "not part of this state"
    /// (an old phone, or a list that could not be read): the Watch keeps what
    /// it has. `[]` is an explicit empty list and clears the Watch's copy.
    public let players: [WatchPlayer]?

    public init(proUnlocked: Bool, completedMatchCount: Int, players: [WatchPlayer]? = nil) {
        self.proUnlocked = proUnlocked
        self.completedMatchCount = completedMatchCount
        self.players = players
    }

    public var applicationContext: [String: Any] {
        var context: [String: Any] = [Self.proUnlockedKey: proUnlocked, Self.completedMatchCountKey: completedMatchCount]
        // JSON `Data` (a property list type) rather than an array of
        // dictionaries, so the entries' types survive the round trip exactly.
        if let players, let data = try? JSONEncoder().encode(players) {
            context[Self.playersKey] = data
        }
        return context
    }

    /// `nil` for a dictionary that is not this state (missing or mistyped keys).
    /// The `players` entry is optional: absent or not a JSON array it reads as
    /// `nil`; an array keeps its readable entries.
    public init?(applicationContext: [String: Any]) {
        guard let pro = applicationContext[Self.proUnlockedKey] as? Bool,
              let count = applicationContext[Self.completedMatchCountKey] as? Int else { return nil }
        self.init(
            proUnlocked: pro,
            completedMatchCount: max(0, count),
            players: (applicationContext[Self.playersKey] as? Data).flatMap(Self.decodePlayers)
        )
    }

    /// Each element on its own, so one malformed entry costs only itself.
    private static func decodePlayers(from data: Data) -> [WatchPlayer]? {
        guard let entries = try? JSONDecoder().decode([Lossy<WatchPlayer>].self, from: data) else { return nil }
        return entries.compactMap(\.value)
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}

/// The phone's last reported state, kept on the Watch so buying Pro on the
/// phone unlocks it even when the Watch cannot reach Apple's servers.
public struct WatchEntitlementCache: Sendable {
    public static let proKey = "watchPhoneProUnlocked"
    public static let countKey = "watchPhoneCompletedMatchCount"

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var userDefaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public var phoneProUnlocked: Bool { userDefaults.bool(forKey: Self.proKey) }
    public var phoneCompletedMatchCount: Int { max(0, userDefaults.integer(forKey: Self.countKey)) }

    public func apply(_ context: PhoneStateContext) {
        userDefaults.set(context.proUnlocked, forKey: Self.proKey)
        userDefaults.set(context.completedMatchCount, forKey: Self.countKey)
    }
}

/// The Watch's own StoreKit read, behind a protocol so the decision is tested
/// with a fake and the real `Transaction.currentEntitlements` stays in the
/// Watch target.
public protocol WatchEntitlementReading: Sendable {
    func isProEntitled() async -> Bool
}

/// Everything the Watch's Home screen needs to decide whether Start Match is
/// allowed: Pro is StoreKit Pro OR the phone's Pro (a phone "not Pro" never
/// overrides a StoreKit "Pro"), and the count is shared with the phone.
@MainActor
@Observable
public final class WatchAccess {
    private let counter: WatchLifetimeCounter
    private let cache: WatchEntitlementCache
    private let entitlements: any WatchEntitlementReading
    private let limit: Int

    private(set) var storeKitPro = false
    private(set) var phonePro: Bool
    private(set) var phoneCount: Int

    public init(
        counter: WatchLifetimeCounter,
        cache: WatchEntitlementCache,
        entitlements: any WatchEntitlementReading,
        limit: Int = WatchDemoGate.demoMatchLimit
    ) {
        self.counter = counter
        self.cache = cache
        self.entitlements = entitlements
        self.limit = limit
        phonePro = cache.phoneProUnlocked
        phoneCount = cache.phoneCompletedMatchCount
    }

    public var isPro: Bool { storeKitPro || phonePro }

    public var effectiveCompletedCount: Int { max(counter.count, phoneCount) }

    /// Read when a match is about to start; a live match is never re-checked.
    public var canStartMatch: Bool {
        WatchDemoGate.canStartMatch(isPro: isPro, localCount: counter.count, phoneCount: phoneCount, limit: limit)
    }

    public func refreshEntitlements() async {
        storeKitPro = await entitlements.isProEntitled()
    }

    public func apply(_ context: PhoneStateContext) {
        cache.apply(context)
        phonePro = context.proUnlocked
        phoneCount = context.completedMatchCount
    }
}

/// How the phone pushes its state to the Watch; the real one is `PhoneWatchSync`.
public protocol PhoneStatePushing: Sendable {
    func push(_ context: PhoneStateContext)
}

/// Pushes the phone's current Pro flag, demo count and saved-player list.
/// Every trigger (session activation, an entitlement change, a saved or
/// imported match, the app becoming active, Manage Players closing) just calls
/// `publish()`: the state is read fresh each time, so the order cannot matter,
/// and an unchanged state is dropped by the pusher.
@MainActor
public final class PhoneStatePublisher {
    private let pusher: any PhoneStatePushing
    private let isPro: @MainActor () -> Bool
    private let completedMatchCount: @MainActor () -> Int
    private let players: @MainActor () -> [WatchPlayer]?

    /// `players` returns `nil` when the list cannot be read right now (the
    /// Watch then keeps its copy); it is capped and cleaned here.
    public init(
        pusher: any PhoneStatePushing,
        isPro: @escaping @MainActor () -> Bool,
        completedMatchCount: @escaping @MainActor () -> Int,
        players: @escaping @MainActor () -> [WatchPlayer]? = { nil }
    ) {
        self.pusher = pusher
        self.isPro = isPro
        self.completedMatchCount = completedMatchCount
        self.players = players
    }

    public func publish() {
        pusher.push(PhoneStateContext(
            proUnlocked: isPro(),
            completedMatchCount: completedMatchCount(),
            players: players().map(WatchPlayerList.normalized)
        ))
    }
}
