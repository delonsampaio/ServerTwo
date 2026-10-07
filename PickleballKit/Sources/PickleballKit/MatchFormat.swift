public enum MatchFormat: Int, Codable, Sendable, CaseIterable {
    case bestOfOne = 1
    case bestOfThree = 3
    case bestOfFive = 5

    public var gamesToWin: Int {
        (rawValue / 2) + 1
    }
}
