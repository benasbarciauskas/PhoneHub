import CoreGraphics
import XCTest
@testable import PhoneHubCore

final class StageGeometryTests: XCTestCase {
    func testCenteredRectCentersSmallerMirrorInStage() {
        let container = CGRect(x: 10, y: 20, width: 400, height: 800)
        let rect = centeredRect(forContentSize: CGSize(width: 316, height: 696), within: container, inset: 12)

        XCTAssertEqual(rect.width, 316, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 696, accuracy: 0.0001)
        XCTAssertCentered(rect, in: container)
        XCTAssertEqual(rect.minX, 52, accuracy: 0.0001)
        XCTAssertEqual(rect.minY, 72, accuracy: 0.0001)
    }

    func testCenteredRectKeepsLargerMirrorFixedSizeAndCentered() {
        let container = CGRect(x: 50, y: 100, width: 200, height: 300)
        let rect = centeredRect(forContentSize: CGSize(width: 316, height: 696), within: container, inset: 12)

        XCTAssertEqual(rect.width, 316, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 696, accuracy: 0.0001)
        XCTAssertCentered(rect, in: container)
        XCTAssertEqual(rect.minX, -8, accuracy: 0.0001)
        XCTAssertEqual(rect.minY, -98, accuracy: 0.0001)
    }

    func testRequiredStageSizeIncludesInsetOnAllSides() {
        let size = requiredStageSize(forMirrorSize: CGSize(width: 316, height: 696), inset: 12)

        XCTAssertEqual(size.width, 340, accuracy: 0.0001)
        XCTAssertEqual(size.height, 720, accuracy: 0.0001)
    }

    func testRequiredStageSizeClampsNegativeInsetAndMirrorSize() {
        let size = requiredStageSize(forMirrorSize: CGSize(width: -10, height: 20), inset: -8)

        XCTAssertEqual(size.width, 0, accuracy: 0.0001)
        XCTAssertEqual(size.height, 20, accuracy: 0.0001)
    }

    private func XCTAssertCentered(_ rect: CGRect,
                                   in container: CGRect,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        XCTAssertEqual(rect.midX, container.midX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rect.midY, container.midY, accuracy: 0.0001, file: file, line: line)
    }
}
