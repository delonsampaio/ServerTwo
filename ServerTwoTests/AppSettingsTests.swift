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

    func testTheLiveActivityDefaultsToOn() {
        XCTAssertTrue(AppSettings(userDefaults: freshDefaults()).liveActivityEnabled)
    }

    func testTheLiveActivitySettingIsRemembered() {
        let defaults = freshDefaults()
        AppSettings(userDefaults: defaults).liveActivityEnabled = false
        XCTAssertFalse(AppSettings(userDefaults: defaults).liveActivityEnabled)
        AppSettings(userDefaults: defaults).liveActivityEnabled = true
        XCTAssertTrue(AppSettings(userDefaults: defaults).liveActivityEnabled)
    }
}
