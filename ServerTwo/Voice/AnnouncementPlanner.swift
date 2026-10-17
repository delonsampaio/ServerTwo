import PickleballKit

/// Turns "what changed on the scoring screen" into the sentences to speak.
/// Pure and stateless. Every returned line is a full sentence ending in a
/// period; `VoiceAnnouncer` joins them with a space into one utterance.
///
/// One same-game change composes at most four slots, in this order:
/// 1. prefix: "Side out." + "<name> serving." (two sentences) or
///    "Second server." (forward moves only),
/// 2. the score call,
/// 3. "Switch sides." / "Switch back." (last game of the format only),
/// 4. "Match point." / "Game point." (only when the call was spoken).
enum AnnouncementPlanner {
    static func plan(
        from old: AnnouncementSnapshot,
        to new: AnnouncementSnapshot,
        configuration: GameConfiguration,
        matchFormat: MatchFormat,
        teamAName: String,
        teamBName: String
    ) -> [String] {
        func name(_ team: Team) -> String { team == .teamA ? teamAName : teamBName }

        // The completed-game count is checked FIRST so one multi-field change
        // (e.g. a correction that crosses the side-switch threshold and ends
        // the game) never produces conflicting lines.
        if new.gameIndex > old.gameIndex {
            guard let done = new.lastCompleted else {
                return [scoreCall(new, configuration: configuration) + "."]
            }
            let winner: Team = done.winner ?? (done.teamAScore >= done.teamBScore ? .teamA : .teamB)
            let winnerScore = winner == .teamA ? done.teamAScore : done.teamBScore
            let loserScore = winner == .teamA ? done.teamBScore : done.teamAScore
            if new.isMatchOver {
                if matchFormat == .bestOfOne {
                    return ["Game and match, \(name(winner)), \(winnerScore) to \(loserScore)."]
                }
                let matchWinner: Team = new.teamAGamesWon > new.teamBGamesWon ? .teamA : .teamB
                let winnerGames = matchWinner == .teamA ? new.teamAGamesWon : new.teamBGamesWon
                let loserGames = matchWinner == .teamA ? new.teamBGamesWon : new.teamAGamesWon
                return [
                    "Game \(new.gameIndex) to \(name(winner)), \(winnerScore) to \(loserScore).",
                    "Game and match, \(name(matchWinner)), \(winnerGames) games to \(loserGames).",
                ]
            }
            // Teams change ends after every completed game, and the next game's
            // first server is the opponent of this game's first server, not the
            // winner (Rule 21.F.2); `new.servingTeam` is that fresh game's server.
            return [
                "Game \(new.gameIndex) to \(name(winner)), \(winnerScore) to \(loserScore).",
                "Switch sides.",
                "Next game, \(name(new.servingTeam)) serving, \(scoreCall(new, configuration: configuration)).",
            ]
        }

        // An undo that reopened the previous game: the restored call, plus the
        // stakes when the restored board is game/match point (same as an undo
        // inside a game). No prefix and no switch line.
        if new.gameIndex < old.gameIndex {
            var restored = [scoreCall(new, configuration: configuration) + "."]
            if let stakes = pointStakes(new, configuration: configuration, matchFormat: matchFormat) {
                restored.append(stakes)
            }
            return restored
        }

        var lines: [String] = []
        if new.teamATimeoutsRemaining < old.teamATimeoutsRemaining {
            lines.append("Timeout, \(teamAName).")
        }
        if new.teamBTimeoutsRemaining < old.teamBTimeoutsRemaining {
            lines.append("Timeout, \(teamBName).")
        }
        if !lines.isEmpty { return lines }

        let scoresUnchanged = old.teamAScore == new.teamAScore && old.teamBScore == new.teamBScore
        let callChanged = !scoresUnchanged
            || old.servingTeam != new.servingTeam
            || old.serverNumber != new.serverNumber

        // 1. Referee calls (Rule 17.D.4, 17.D.5): only when nobody scored, on a
        // FORWARD move, in side-out scoring. An undo that restores the serve
        // must not announce a side out that did not just happen.
        if callChanged, scoresUnchanged, new.moveCount > old.moveCount,
           configuration.scoringFormat == .sideOut {
            if old.servingTeam != new.servingTeam {
                // Say who has the serve now: "Side out." alone does not tell a
                // noisy court which team that is.
                lines.append("Side out.")
                lines.append("\(name(new.servingTeam)) serving.")
            } else if configuration.playMode == .doubles, old.serverNumber == .one, new.serverNumber == .two {
                lines.append("Second server.")
            }
        }

        // 2. The score call.
        if callChanged {
            lines.append(scoreCall(new, configuration: configuration) + ".")
        }

        // 3. Mid-game change of ends: last game of the format only (Rule 21.B).
        if matchFormat.isLastGame(index: new.gameIndex) {
            if !old.hasSideSwitched && new.hasSideSwitched {
                lines.append("Switch sides.")
            } else if old.hasSideSwitched && !new.hasSideSwitched {
                lines.append("Switch back.")
            }
        }

        // 4. Stakes, only alongside a spoken call (never on a timeout undo).
        if callChanged, let stakes = pointStakes(new, configuration: configuration, matchFormat: matchFormat) {
            lines.append(stakes)
        }
        return lines
    }

    /// Serving team's score, receiving team's score, then (doubles side-out
    /// only) the server number. Rally scoring and singles omit it
    /// (Rules 6.B, 14.A).
    static func scoreCall(_ snapshot: AnnouncementSnapshot, configuration: GameConfiguration) -> String {
        let servingScore = snapshot.servingTeam == .teamA ? snapshot.teamAScore : snapshot.teamBScore
        let receivingScore = snapshot.servingTeam == .teamA ? snapshot.teamBScore : snapshot.teamAScore
        var parts = ["\(servingScore)", "\(receivingScore)"]
        if configuration.playMode == .doubles, configuration.scoringFormat == .sideOut {
            parts.append("\(snapshot.serverNumber.rawValue)")
        }
        return parts.joined(separator: ", ")
    }

    /// "Match point." / "Game point." when a team that can end the game on the
    /// next point exists (a courtesy call, not a rulebook call). Side-out and
    /// rally freeze: only the serving team can; rally without freeze: either.
    static func pointStakes(
        _ snapshot: AnnouncementSnapshot,
        configuration: GameConfiguration,
        matchFormat: MatchFormat
    ) -> String? {
        let eligible: [Team]
        switch configuration.scoringFormat {
        case .sideOut:
            eligible = [snapshot.servingTeam]
        case .rally(let freeze):
            eligible = freeze ? [snapshot.servingTeam] : [.teamA, .teamB]
        }
        let winners = eligible.filter { canWinOnNextPoint($0, in: snapshot, configuration: configuration) }
        guard !winners.isEmpty else { return nil }
        let clinches = winners.contains { team in
            let games = team == .teamA ? snapshot.teamAGamesWon : snapshot.teamBGamesWon
            return games + 1 >= matchFormat.gamesToWin
        }
        return clinches ? "Match point." : "Game point."
    }

    /// `isCompletedGameScore` is symmetric (it looks at max/min), so the team
    /// must also be strictly ahead after the point; otherwise a trailing
    /// serving team would be reported at game point whenever the other team
    /// already holds a winning-looking score (reachable in rally freeze).
    private static func canWinOnNextPoint(
        _ team: Team,
        in snapshot: AnnouncementSnapshot,
        configuration: GameConfiguration
    ) -> Bool {
        let ownNext = (team == .teamA ? snapshot.teamAScore : snapshot.teamBScore) + 1
        let opponent = team == .teamA ? snapshot.teamBScore : snapshot.teamAScore
        guard ownNext > opponent else { return false }
        return team == .teamA
            ? configuration.isCompletedGameScore(teamA: ownNext, teamB: opponent)
            : configuration.isCompletedGameScore(teamA: opponent, teamB: ownNext)
    }
}
