import CoreGraphics
import XCTest
@testable import PhoneHubCore

final class StageGeometryTests: XCTestCase {
    func testFitStepShrinksWhenCurrentWidthIsLargerThanTarget() {
        XCTAssertEqual(fitStep(current: CGSize(width: 401, height: 600),
                               target: CGSize(width: 400, height: 700)),
                       .smaller)
    }

    func testFitStepShrinksWhenCurrentHeightIsLargerThanTarget() {
        XCTAssertEqual(fitStep(current: CGSize(width: 300, height: 701),
                               target: CGSize(width: 400, height: 700)),
                       .smaller)
    }

    func testFitStepGrowsWhenCurrentFitsTarget() {
        XCTAssertEqual(fitStep(current: CGSize(width: 300, height: 600),
                               target: CGSize(width: 400, height: 700)),
                       .larger)
    }

    func testFitStepProbesLargerWhenCurrentIsNearTarget() {
        XCTAssertEqual(fitStep(current: CGSize(width: 365, height: 665),
                               target: CGSize(width: 400, height: 700)),
                       .larger)
    }

    func testFitStepProbesLargerWhenCurrentEqualsTarget() {
        XCTAssertEqual(fitStep(current: CGSize(width: 400, height: 700),
                               target: CGSize(width: 400, height: 700)),
                       .larger)
    }

    func testFitStepLeavesOvershootRevertToWindowLoop() {
        let fittingSize = CGSize(width: 316, height: 696)
        let overshootSize = CGSize(width: 406, height: 890)
        let target = CGSize(width: 500, height: 752)

        XCTAssertEqual(fitStep(current: fittingSize, target: target), .larger)
        XCTAssertEqual(fitStep(current: overshootSize, target: target), .smaller)
    }

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

    func testGridTileRectsForRequestedCounts() {
        [1, 2, 4, 5, 9].forEach { count in
            assertGridTileRects(count: count)
        }
    }

    private func assertGridTileRects(count: Int,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        let container = CGRect(x: 10, y: 20, width: 900, height: 600)
        let inset: CGFloat = 20
        let spacing: CGFloat = 10
        let rects = gridTileRects(count: count, within: container, inset: inset, spacing: spacing)
        let insetContainer = container.insetBy(dx: inset, dy: inset)

        XCTAssertEqual(rects.count, count, file: file, line: line)
        rects.forEach { rect in
            XCTAssertGreaterThan(rect.width, 0, file: file, line: line)
            XCTAssertGreaterThan(rect.height, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minX, insetContainer.minX - 0.0001, file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minY, insetContainer.minY - 0.0001, file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxX, insetContainer.maxX + 0.0001, file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxY, insetContainer.maxY + 0.0001, file: file, line: line)
        }

        for leftIndex in rects.indices {
            for rightIndex in rects.indices where rightIndex > leftIndex {
                XCTAssertFalse(rects[leftIndex].intersects(rects[rightIndex]),
                               "Rects \(leftIndex) and \(rightIndex) overlap for count \(count)",
                               file: file,
                               line: line)
            }
        }

        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        for row in 0..<rows {
            let rowRange = (row * columns)..<min((row + 1) * columns, count)
            let rowRects = rowRange.map { rects[$0] }
            guard rowRects.count > 1 else { continue }
            for index in 0..<(rowRects.count - 1) {
                XCTAssertGreaterThanOrEqual(rowRects[index + 1].minX - rowRects[index].maxX,
                                            spacing - 0.0001,
                                            file: file,
                                            line: line)
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
}
