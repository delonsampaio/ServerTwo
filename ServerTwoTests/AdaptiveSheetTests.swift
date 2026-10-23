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

    func testScaledHeightNeverBelowDesignHeight() {
        // xSmall/Small/Medium scale the metric below the design height.
        XCTAssertEqual(SheetDetentPolicy.scaledHeight(design: 320, scaled: 262), 320)
        XCTAssertEqual(SheetDetentPolicy.scaledHeight(design: 320, scaled: 320), 320)
    }

    func testScaledHeightGrowsAboveDesignHeight() {
        XCTAssertEqual(SheetDetentPolicy.scaledHeight(design: 320, scaled: 480), 480)
    }
}
