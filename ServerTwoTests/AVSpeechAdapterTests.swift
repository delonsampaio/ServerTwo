import XCTest
@testable import ServerTwo

@MainActor
final class AVSpeechAdapterTests: XCTestCase {
    func testEnglishDeviceLanguagesAreKept() {
        XCTAssertEqual(AVSpeechSynthesizerAdapter.voiceLanguage(deviceLanguage: "en-US"), "en-US")
        XCTAssertEqual(AVSpeechSynthesizerAdapter.voiceLanguage(deviceLanguage: "en-GB"), "en-GB")
        XCTAssertEqual(AVSpeechSynthesizerAdapter.voiceLanguage(deviceLanguage: "EN-au"), "EN-au")
    }

    func testOtherDeviceLanguagesFallBackToUSEnglish() {
        XCTAssertEqual(AVSpeechSynthesizerAdapter.voiceLanguage(deviceLanguage: "pt-BR"), "en-US")
        XCTAssertEqual(AVSpeechSynthesizerAdapter.voiceLanguage(deviceLanguage: "es-MX"), "en-US")
        XCTAssertEqual(AVSpeechSynthesizerAdapter.voiceLanguage(deviceLanguage: ""), "en-US")
    }
}
