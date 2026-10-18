import XCTest
import SwiftUI
@testable import ServerTwo

/// Only the pure detent policy is unit-tested. `AdaptiveScroll` and the
/// `adaptiveSheetDetents` modifier read the environment, so they are covered
/// by the sheet UI tests and the accessibility audit.
@MainActor
final class AdaptiveSheetTests: XCTestCase {
    func testNormalSizeHasOneDetent() {
        XCTAssertEqual(
            SheetDetentPolicy.detents(height: 320, isAccessibilitySize: false),
            [.height(320)]
        )
    }

    func testAccessibilitySizeAddsLarge() {
        XCTAssertEqual(
            SheetDetentPolicy.detents(height: 320, isAccessibilitySize: true),
            [.height(320), .large]
        )
    }
}
