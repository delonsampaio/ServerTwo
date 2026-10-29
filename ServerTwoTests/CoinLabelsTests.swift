import XCTest
@testable import ServerTwo

/// The coin shows one short label per team, so two teams whose names share an
/// initial ("Delon" / "Daniel") must still read differently on the coin.
@MainActor
final class CoinLabelsTests: XCTestCase {
    private func labels(_ a: String, _ b: String) -> [String] {
        let result = CoinLabels.labels(teamA: a, teamB: b)
        return [result.a, result.b]
    }

    func testDifferentFirstLettersUseTheUppercasedInitials() {
        XCTAssertEqual(labels("Delon", "Yi"), ["D", "Y"])
        XCTAssertEqual(labels("katie", "fred"), ["K", "F"])
    }

    func testSameFirstLetterUsesTwoLetterPrefixes() {
        XCTAssertEqual(labels("Delon", "Daniel"), ["De", "Da"])
    }

    func testSameTwoLettersUseThreeLetterPrefixes() {
        XCTAssertEqual(labels("Delon", "Devon"), ["Del", "Dev"])
    }

    func testIdenticalNamesFallBackToSideLetters() {
        XCTAssertEqual(labels("Delon", "Delon"), ["A", "B"])
        XCTAssertEqual(labels("Delon", "delon"), ["A", "B"])
    }

    func testUnnamedDefaultsFallBackToSideLetters() {
        XCTAssertEqual(labels("Team A", "Team B"), ["A", "B"])
    }

    func testSameFirstLetterIsComparedCaseInsensitively() {
        XCTAssertEqual(labels("delon", "Daniel"), ["De", "Da"])
        XCTAssertEqual(labels("DELON", "daniel"), ["De", "Da"])
    }

    func testPrefixesAreShownWithOnlyTheFirstLetterUppercased() {
        XCTAssertEqual(labels("DELON", "dEVON"), ["Del", "Dev"])
    }

    func testOneNameBeingAPrefixOfTheOtherFallsBack() {
        XCTAssertEqual(labels("Al", "Alex"), ["A", "B"])
        XCTAssertEqual(labels("Alex", "Al"), ["A", "B"])
    }

    func testNamesThatShareMoreThanThreeLettersFallBack() {
        XCTAssertEqual(labels("Delonia", "Delonex"), ["A", "B"])
    }

    func testEmptyNamesFallBackToTheirSideLetters() {
        XCTAssertEqual(labels("", ""), ["A", "B"])
        XCTAssertEqual(labels("   ", ""), ["A", "B"])
        XCTAssertEqual(labels("", "Yi"), ["A", "Y"])
        XCTAssertEqual(labels("Delon", ""), ["D", "B"])
    }

    func testAnEmptyNameNeverProducesTheSameLabelAsTheOtherSide() {
        // Team B's real initial would be "A", the same as Team A's fallback.
        XCTAssertEqual(labels("", "Alex"), ["A", "B"])
        XCTAssertEqual(labels("Bo", ""), ["A", "B"])
    }

    func testLeadingWhitespaceIsSkipped() {
        XCTAssertEqual(labels("  Delon", "Daniel  "), ["De", "Da"])
        XCTAssertEqual(labels("\n Delon", " Yi"), ["D", "Y"])
    }

    func testEmojiFirstCharacterIsOneCharacter() {
        XCTAssertEqual(labels("🎾 Ace", "Yi"), ["🎾", "Y"])
        // Shared emoji and space, then the letters differ: counted per Character.
        XCTAssertEqual(labels("🎾 Ace", "🎾 Bo"), ["🎾 a", "🎾 b"])
        XCTAssertEqual(labels("🎾", "🎾"), ["A", "B"])
    }

    func testCombiningCharactersCountAsOneCharacter() {
        // "e" + combining acute is a single Character, so the prefix is not
        // cut between the letter and its accent.
        let accented = "e\u{301}lan"
        XCTAssertEqual(labels(accented, "Yi"), ["E\u{301}", "Y"])
        // An accented letter is a different letter from the plain one...
        XCTAssertEqual(labels(accented, "Eva"), ["E\u{301}", "E"])
        // ...and a shared accented first character is one Character of the prefix.
        XCTAssertEqual(labels(accented, "e\u{301}va"), ["E\u{301}l", "E\u{301}v"])
    }

    func testTeamDisplayNamesWithAmpersand() {
        XCTAssertEqual(labels("Delon & Katie", "Dan & Kim"), ["De", "Da"])
    }

    func testLabelsAreNeverEqual() {
        let names = [
            "", " ", "Delon", "delon", "Daniel", "Al", "Alex", "Team A", "Team B",
            "🎾", "🎾 Ace", "e\u{301}lan", "Delon & Katie", "Dan & Kim", "ß", "SS",
        ]
        for a in names {
            for b in names {
                let result = CoinLabels.labels(teamA: a, teamB: b)
                XCTAssertNotEqual(result.a, result.b, "'\(a)' vs '\(b)'")
                XCTAssertFalse(result.a.isEmpty, "'\(a)' vs '\(b)'")
                XCTAssertFalse(result.b.isEmpty, "'\(a)' vs '\(b)'")
            }
        }
    }
}
