import PickleballKit

/// Turns "what changed on the scoring screen" into the sentences to speak.
/// Pure and stateless. Every returned line is a full sentence ending in a
/// period; `VoiceAnnouncer` joins them with a space into one utterance.
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
                    return ["\(name(winner)) wins, \(winnerScore) to \(loserScore)."]
                }
                let matchWinner: Team = new.teamAGamesWon > new.teamBGamesWon ? .teamA : .teamB
                let winnerGames = matchWinner == .teamA ? new.teamAGamesWon : new.teamBGamesWon
                let loserGames = matchWinner == .teamA ? new.teamBGamesWon : new.teamAGamesWon
                return [
                    "Game \(new.gameIndex) to \(name(winner)), \(winnerScore) to \(loserScore).",
                    "\(name(matchWinner)) wins the match, \(winnerGames) to \(loserGames).",
                ]
            }
            return [
                "Game \(new.gameIndex) to \(name(winner)), \(winnerScore) to \(loserScore).",
                "Next game, \(scoreCall(new, configuration: configuration)).",
            ]
        }

        // An undo that reopened the previous game: just the restored call.
        if new.gameIndex < old.gameIndex {
            return [scoreCall(new, configuration: configuration) + "."]
        }

        var lines: [String] = []
        if new.teamATimeoutsRemaining < old.teamATimeoutsRemaining {
            lines.append("Timeout, \(teamAName).")
        }
        if new.teamBTimeoutsRemaining < old.teamBTimeoutsRemaining {
            lines.append("Timeout, \(teamBName).")
        }
        if !lines.isEmpty { return lines }

        let callChanged = old.teamAScore != new.teamAScore
            || old.teamBScore != new.teamBScore
            || old.servingTeam != new.servingTeam
            || old.serverNumber != new.serverNumber
        if callChanged {
            lines.append(scoreCall(new, configuration: configuration) + ".")
        }
        if !old.hasSideSwitched && new.hasSideSwitched {
            lines.append("Switch sides.")
        } else if old.hasSideSwitched && !new.hasSideSwitched {
            lines.append("Switch back.")
        }
        return lines
    }

    /// Serving team's score, receiving team's score, then (doubles side-out
    /// only) the server number. Rally scoring and singles omit it.
    static func scoreCall(_ snapshot: AnnouncementSnapshot, configuration: GameConfiguration) -> String {
        let servingScore = snapshot.servingTeam == .teamA ? snapshot.teamAScore : snapshot.teamBScore
        let receivingScore = snapshot.servingTeam == .teamA ? snapshot.teamBScore : snapshot.teamAScore
        var parts = ["\(servingScore)", "\(receivingScore)"]
        if configuration.playMode == .doubles, configuration.scoringFormat == .sideOut {
            parts.append("\(snapshot.serverNumber.rawValue)")
        }
        return parts.joined(separator: ", ")
    }
}
