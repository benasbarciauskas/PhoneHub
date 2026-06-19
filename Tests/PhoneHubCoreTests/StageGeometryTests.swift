import CoreGraphics
import XCTest
@testable import PhoneHubCore

final class StageGeometryTests: XCTestCase {
    func testPortraitAspectInWideStageIsHeightLimitedAndCentered() {
        let container = CGRect(x: 10, y: 20, width: 400, height: 800)
        let rect = aspectFitRect(aspectRatio: 316 / 696, in: container, inset: 8)

        XCTAssertLessThanOrEqual(rect.height, 800 - 16 + 0.0001)
        XCTAssertEqual(rect.height, 800 - 16, accuracy: 0.0001)
        XCTAssertCentered(rect, in: container)
        XCTAssertWithin(rect, container)
    }

    func testPortraitAspectInNarrowStageIsWidthLimitedAndCentered() {
        let container = CGRect(x: -30, y: 50, width: 200, height: 800)
        let rect = aspectFitRect(aspectRatio: 316 / 696, in: container, inset: 8)

        XCTAssertLessThanOrEqual(rect.width, 200 - 16 + 0.0001)
        XCTAssertEqual(rect.width, 200 - 16, accuracy: 0.0001)
        XCTAssertCentered(rect, in: container)
        XCTAssertWithin(rect, container)
    }

    func testSquareAspectFitsInsideRect() {
        let container = CGRect(x: 4, y: 6, width: 320, height: 180)
        let rect = aspectFitRect(aspectRatio: 1, in: container, inset: 8)

        XCTAssertEqual(rect.width, rect.height, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(rect.width, 320 - 16 + 0.0001)
        XCTAssertLessThanOrEqual(rect.height, 180 - 16 + 0.0001)
        XCTAssertCentered(rect, in: container)
        XCTAssertWithin(rect, container)
    }

    func testZeroInsetFillsContainerOnLimitingAxis() {
        let container = CGRect(x: 0, y: 0, width: 400, height: 800)
        let rect = aspectFitRect(aspectRatio: 316 / 696, in: container, inset: 0)

        XCTAssertEqual(rect.height, container.height, accuracy: 0.0001)
        XCTAssertCentered(rect, in: container)
        XCTAssertWithin(rect, container)
    }

    func testResultNeverExceedsContainer() {
        let containers = [
            CGRect(x: 0, y: 0, width: 400, height: 800),
            CGRect(x: 100, y: -100, width: 200, height: 800),
            CGRect(x: -20, y: 70, width: 333, height: 333),
            CGRect(x: 10, y: 20, width: 40, height: 20)
        ]
        let aspects: [CGFloat] = [316 / 696, 9 / 19.5, 1, 2.5]

        for container in containers {
            for aspect in aspects {
                let rect = aspectFitRect(aspectRatio: aspect, in: container, inset: 8)
                XCTAssertWithin(rect, container)
            }
        }
    }

    private func XCTAssertCentered(_ rect: CGRect,
                                   in container: CGRect,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        XCTAssertEqual(rect.midX, container.midX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rect.midY, container.midY, accuracy: 0.0001, file: file, line: line)
    }

    private func XCTAssertWithin(_ rect: CGRect,
                                 _ container: CGRect,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(rect.minX, container.minX - 0.0001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY, container.minY - 0.0001, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX, container.maxX + 0.0001, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, container.maxY + 0.0001, file: file, line: line)
    }
}
