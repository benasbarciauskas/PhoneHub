import XCTest
@testable import PhoneHubCore

final class MirrorDeviceMatchTests: XCTestCase {
    func testMatchingClickedModelAndMirroredTitleReturnsMatch() {
        XCTAssertEqual(compareMirroredDevice(clickedModel: "iPhone 13 Pro",
                                              mirroredTitle: "iPhone 13 Pro"),
                       .match)
    }

    func testComparisonIgnoresCaseAndOuterWhitespace() {
        XCTAssertEqual(compareMirroredDevice(clickedModel: " iPhone 13 Pro ",
                                              mirroredTitle: "IPHONE 13 PRO"),
                       .match)
    }

    func testDifferentMirroredTitleReturnsActualDevice() {
        XCTAssertEqual(compareMirroredDevice(clickedModel: "iPhone 13 Pro",
                                              mirroredTitle: "iPhone 16 Pro"),
                       .mismatch(actual: "iPhone 16 Pro"))
    }
}
