import Foundation

/// The short text shown on each side of the coin-flip coin.
///
/// The coin alternates between the two teams' labels and lands on the
/// winner's, so the two labels must differ: with plain initials, "Delon" vs
/// "Daniel" (or the unnamed "Team A" vs "Team B") would show the same letter
/// for both outcomes and nothing on the coin would say who won.
enum CoinLabels {
    /// Longest label that still fits the coin at a readable size.
    private static let maxLength = 3

    static func labels(teamA: String, teamB: String) -> (a: String, b: String) {
        // Side letters are the fallback for every case that cannot be told
        // apart (or has no name to show).
        let fallback = (a: "A", b: "B")
        // `Character`, not bytes or scalars, so an emoji or a letter with a
        // combining accent is never cut in half.
        let a = Array(teamA.trimmingCharacters(in: .whitespacesAndNewlines))
        let b = Array(teamB.trimmingCharacters(in: .whitespacesAndNewlines))

        // An empty name has nothing to show, so its side keeps its letter;
        // the other side keeps its initial unless that would collide.
        if a.isEmpty || b.isEmpty {
            let result = (
                a: a.isEmpty ? fallback.a : label(a, length: 1),
                b: b.isEmpty ? fallback.b : label(b, length: 1)
            )
            return result.a == result.b ? fallback : result
        }

        // The shortest prefix at which the names differ. Both names must be
        // that long: "Al" vs "Alex" would otherwise differ at three
        // characters only because one of them ran out, which reads as
        // "Al" vs "Ale" and says nothing about who is who.
        for length in 1...maxLength where a.count >= length && b.count >= length {
            if !samePrefix(a, b, length: length) {
                let result = (a: label(a, length: length), b: label(b, length: length))
                // Uppercasing can merge two different characters (e.g. "ß"
                // becomes "SS"); never show two equal labels.
                return result.a == result.b ? fallback : result
            }
        }
        return fallback
    }

    private static func samePrefix(_ a: [Character], _ b: [Character], length: Int) -> Bool {
        String(a.prefix(length)).lowercased() == String(b.prefix(length)).lowercased()
    }

    /// First letter uppercased, the rest lowercased ("DELON" -> "Del").
    private static func label(_ name: [Character], length: Int) -> String {
        let prefix = name.prefix(length)
        guard let first = prefix.first else { return "" }
        return String(first).uppercased() + String(prefix.dropFirst()).lowercased()
    }
}
