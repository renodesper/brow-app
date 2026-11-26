import XCTest
@testable import BrowCore

final class NotchSizingTests: XCTestCase {
    func testWithNoCustomSizeTheNotchIsUsed() {
        let size = NotchSizing.resolved(detectedWidth: 185, detectedHeight: 32, customWidth: nil, customHeight: nil)
        XCTAssertEqual(size.width, 186)
        XCTAssertEqual(size.height, 32)
    }

    func testACustomSizeIsUsed() {
        let size = NotchSizing.resolved(detectedWidth: 185, detectedHeight: 32, customWidth: 200, customHeight: 34)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 34)
    }

    func testACustomSizeIsNeverSmallerThanTheNotch() {
        let size = NotchSizing.resolved(detectedWidth: 186, detectedHeight: 32, customWidth: 150, customHeight: 20)
        XCTAssertEqual(size.width, 186)
        XCTAssertEqual(size.height, 32)
    }

    func testWidthsAreEvenAndHeightsWhole() {
        let size = NotchSizing.resolved(detectedWidth: 186, detectedHeight: 32, customWidth: 201.2, customHeight: 33.1)
        XCTAssertEqual(size.width, 202)
        XCTAssertEqual(size.height, 34)
    }

    func testTheStartingSizeIsALittleMoreThanTheNotch() {
        let size = NotchSizing.starting(detectedWidth: 185, detectedHeight: 32)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 34)
    }
}
