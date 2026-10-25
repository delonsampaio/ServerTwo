import Foundation

/// The VoiceOver wording that is built from data (rather than a fixed string
/// in a view), kept pure so it can be unit-tested.
enum AccessibilityText {
    /// "<name>, <score> points", plus ", serving" for the serving team and, in
    /// doubles side-out scoring only, ", server 1" / ", server 2" (the caller
    /// passes nil elsewhere). The text must keep starting "<name>, <N> points":
    /// UI tests match "<N> points" and parse the digits after the first ", ".
    static func scoreZoneLabel(name: String, score: Int, isServing: Bool, serverNumber: Int?) -> String {
        let base = "\(name), \(score) points"
        guard isServing else { return base }
        guard let serverNumber else { return base + ", serving" }
        return base + ", serving, server \(serverNumber)"
    }

    static let scoreZoneHint =
        "Double tap to score a point. Use the Actions rotor to correct the score."

    static func resultWord(didWin: Bool) -> String {
        didWin ? "Won" : "Lost"
    }

    /// Results joined with ", ". The caller passes them in display order.
    static func recentFormValue(_ form: [Bool]) -> String {
        form.map { resultWord(didWin: $0) }.joined(separator: ", ")
    }

    /// `scoreAfter` is the running score after the point, like "4 to 2" (not "4-2", which VoiceOver may read with a minus).
    static func pointRowLabel(sequence: Int, scorerName: String, scoreAfter: String) -> String {
        "Point \(sequence), \(scorerName) scored, \(scoreAfter)"
    }
}
