import Foundation

/// The VoiceOver wording that is built from data (rather than a fixed string
/// in a view), kept pure so it can be unit-tested.
enum AccessibilityText {
    /// "<name>, <score> points", plus ", serving" for the serving team and, in
    /// doubles side-out scoring only, ", server 1" / ", server 2" (the caller
    /// passes nil elsewhere); then, for a doubles side-out team whose name splits
    /// into two, ", Delon on the right, Katie on the left". The text must keep starting "<name>, <N> points":
    /// UI tests match "<N> points" and parse the digits after the first ", ".
    static func scoreZoneLabel(
        name: String, score: Int, isServing: Bool, serverNumber: Int?,
        positions: PartnerPositions? = nil
    ) -> String {
        var label = "\(name), \(score) points"
        if isServing {
            label += serverNumber.map { ", serving, server \($0)" } ?? ", serving"
        }
        // Last, so the "<name>, <N> points" prefix and the serving words stay as
        // they were. The badges are inside this one element, so VoiceOver can
        // only learn the positions from here.
        if let positions { label += ", \(positions.spokenSummary)" }
        return label
    }

    static let scoreZoneHint =
        "Double tap to score a point. Use the Actions rotor to correct the score."

    /// Same hint when the card shows partner positions: the swap lives in the
    /// correction sheet, which the "Correct score" action opens.
    static let scoreZoneHintWithPositions =
        "Double tap to score a point. Use the Actions rotor to correct the score or swap partner positions."

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
