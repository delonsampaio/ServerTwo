import XCTest
@testable import ServerTwo

@MainActor
final class AppSettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    func testTheVoiceAnnouncerIsOffForANewUser() {
        XCTAssertFalse(AppSettings(userDefaults: freshDefaults()).voiceAnnouncerEnabled)
    }

    func testTurningTheVoiceAnnouncerOnIsRemembered() {
        let defaults = freshDefaults()
        AppSettings(userDefaults: defaults).voiceAnnouncerEnabled = true
        XCTAssertTrue(AppSettings(userDefaults: defaults).voiceAnnouncerEnabled)
    }

    func testHapticsStillDefaultToOn() {
        XCTAssertTrue(AppSettings(userDefaults: freshDefaults()).hapticsEnabled)
    }
}
