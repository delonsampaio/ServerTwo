#if DEBUG
// Sample content for the `-Debug-DemoLiveActivity` launch argument (see MyApp).
extension PickleballActivityAttributes {
    static let debugDemo = PickleballActivityAttributes(
        teamAName: "Alex & Sam", teamBName: "Jo & Pat",
        matchFormatSummary: "Doubles • Best of 3", showsGamesWon: true
    )
}

extension PickleballActivityAttributes.ContentState {
    static let debugDemoMidGame = PickleballActivityAttributes.ContentState(
        teamAScore: 7, teamBScore: 5, teamAGamesWon: 1, teamBGamesWon: 0,
        servingTeamRawValue: "teamA", serverNumber: 2, isMatchOver: false
    )
}
#endif
