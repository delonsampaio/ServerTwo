import Foundation

/// The VoiceOver wording that is built from data (rather than a fixed string
/// in a view), kept pure so it can be unit-tested.
enum AccessibilityText {
    /// "<name>, <score> points", plus ", serving" for the serving team. The
    /// text must keep starting "<name>, <N> points": UI tests match
    /// "<N> points" and parse the digits after the first ", ".
    static func scoreZoneLabel(name: String, score: Int, isServing: Bool) -> String {
        let base = "\(name), \(score) points"
        return isServing ? base + ", serving" : base
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

    /// `scoreAfter` is the running score after the point, like "4-2".
    static func pointRowLabel(sequence: Int, scorerName: String, scoreAfter: String) -> String {
        "Point \(sequence), \(scorerName) scored, \(scoreAfter)"
    }
}
