import CoreGraphics
import XCTest
@testable import PhoneHubCore

final class TapCoordinateMappingTests: XCTestCase {
    func testMapsCenterThroughRetinaScreenshotIntoMirroirPoints() {
        let point = mapClickToDevicePoint(
            clickInView: CGPoint(x: 150, y: 250),
            viewSize: CGSize(width: 300, height: 500),
            imagePixelSize: CGSize(width: 820, height: 1796),
            deviceSpaceSize: CGSize(width: 410, height: 898)
        )

        assertPoint(point, x: 205, y: 449)
    }

    func testRemovesSideLetterboxingBeforeMapping() {
        let left = mapClickToDevicePoint(
            clickInView: CGPoint(x: 75, y: 0),
            viewSize: CGSize(width: 300, height: 300),
            imagePixelSize: CGSize(width: 100, height: 200),
            deviceSpaceSize: CGSize(width: 100, height: 200)
        )
        let right = mapClickToDevicePoint(
            clickInView: CGPoint(x: 225, y: 300),
            viewSize: CGSize(width: 300, height: 300),
            imagePixelSize: CGSize(width: 100, height: 200),
            deviceSpaceSize: CGSize(width: 100, height: 200)
        )

        assertPoint(left, x: 0, y: 0)
        assertPoint(right, x: 100, y: 200)
    }

    func testRemovesTopAndBottomLetterboxingBeforeMapping() {
        let point = mapClickToDevicePoint(
            clickInView: CGPoint(x: 150, y: 150),
            viewSize: CGSize(width: 300, height: 300),
            imagePixelSize: CGSize(width: 400, height: 200),
            deviceSpaceSize: CGSize(width: 800, height: 400)
        )

        assertPoint(point, x: 400, y: 200)
    }

    func testClampsClicksInLetterboxToImageEdges() {
        let before = mapClickToDevicePoint(
            clickInView: CGPoint(x: -50, y: -50),
            viewSize: CGSize(width: 300, height: 300),
            imagePixelSize: CGSize(width: 100, height: 200),
            deviceSpaceSize: CGSize(width: 1080, height: 2400)
        )
        let after = mapClickToDevicePoint(
            clickInView: CGPoint(x: 500, y: 500),
            viewSize: CGSize(width: 300, height: 300),
            imagePixelSize: CGSize(width: 100, height: 200),
            deviceSpaceSize: CGSize(width: 1080, height: 2400)
        )

        assertPoint(before, x: 0, y: 0)
        assertPoint(after, x: 1080, y: 2400)
    }

    func testMapsNonUniformImageAndDeviceScales() {
        let point = mapClickToDevicePoint(
            clickInView: CGPoint(x: 100, y: 100),
            viewSize: CGSize(width: 200, height: 200),
            imagePixelSize: CGSize(width: 1000, height: 500),
            deviceSpaceSize: CGSize(width: 400, height: 300)
        )

        assertPoint(point, x: 200, y: 150)
    }

    func testInvalidSizesReturnZeroInsteadOfNaN() {
        let zeroImage = mapClickToDevicePoint(
            clickInView: CGPoint(x: 1, y: 1),
            viewSize: CGSize(width: 100, height: 100),
            imagePixelSize: .zero,
            deviceSpaceSize: CGSize(width: 100, height: 100)
        )
        let infiniteView = mapClickToDevicePoint(
            clickInView: CGPoint(x: 1, y: 1),
            viewSize: CGSize(width: CGFloat.infinity, height: 100),
            imagePixelSize: CGSize(width: 100, height: 100),
            deviceSpaceSize: CGSize(width: 100, height: 100)
        )

        assertPoint(zeroImage, x: 0, y: 0)
        assertPoint(infiniteView, x: 0, y: 0)
    }

    func testParsesMirroirConnectedWindowSize() {
        XCTAssertEqual(
            parseMirroirWindowSize(
                "Connected — mirroring active (window: 410x898, pos=(12,34), portrait)"
            ),
            CGSize(width: 410, height: 898)
        )
    }

    func testRejectsMissingMalformedOrNonPositiveMirroirWindowSize() {
        XCTAssertNil(parseMirroirWindowSize("Paused — connection paused"))
        XCTAssertNil(parseMirroirWindowSize("Connected (window: 410 by 898)"))
        XCTAssertNil(parseMirroirWindowSize("Connected (window: 0x898)"))
        XCTAssertNil(parseMirroirWindowSize("Connected (window: 410x-1)"))
    }

    private func assertPoint(
        _ point: CGPoint,
        x: CGFloat,
        y: CGFloat,
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(point.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: accuracy, file: file, line: line)
    }
}
