import XCTest
@testable import ServerTwo

@MainActor
final class MyAppSpeechOutputTests: XCTestCase {
    func testAUITestLaunchArgumentSelectsTheNullOutput() {
        XCTAssertTrue(MyApp.makeSpeechOutput(arguments: ["-UITest-ResetState"]) is NullSpeechOutput)
        XCTAssertTrue(MyApp.makeSpeechOutput(arguments: ["-UITest-DemoMatchLimit", "1"]) is NullSpeechOutput)
    }

    func testNoUITestArgumentSelectsRealSpeech() {
        XCTAssertFalse(MyApp.makeSpeechOutput(arguments: []) is NullSpeechOutput)
    }
}
