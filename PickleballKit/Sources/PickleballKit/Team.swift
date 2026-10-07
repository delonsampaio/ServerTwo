public enum Team: String, Codable, Sendable, CaseIterable {
    case teamA
    case teamB

    public var opponent: Team {
        self == .teamA ? .teamB : .teamA
    }
}
