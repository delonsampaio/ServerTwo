public enum WinningScore: Int, Codable, Sendable, CaseIterable {
    case eleven = 11
    case fifteen = 15
    case twentyOne = 21

    /// Teams switch ends the first time either team reaches this score.
    /// Formula: ceil(winningScore / 2), which yields the standard 6/8/11
    /// thresholds for games to 11/15/21. Implemented with integer-only
    /// ceiling division — exact for positive integers, no floating point
    /// needed.
    public var sideSwitchThreshold: Int {
        (rawValue + 1) / 2
    }

    /// Per USA Pickleball Rule 10.A: two 1-minute timeouts per team for
    /// games to 11 or 15, three for games to 21.
    public var standardTimeoutsPerTeam: Int {
        self == .twentyOne ? 3 : 2
    }
}
