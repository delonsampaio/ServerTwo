public enum CoinFlip {
    public static func flip<G: RandomNumberGenerator>(using generator: inout G) -> Team {
        Bool.random(using: &generator) ? .teamA : .teamB
    }

    public static func flip() -> Team {
        var generator = SystemRandomNumberGenerator()
        return flip(using: &generator)
    }
}
