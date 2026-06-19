import XCTest
import CoreGraphics
@testable import PhoneHubCore

final class CoordinateMapperTests: XCTestCase {
    // Device 1000x2000 (tall). View 500x500 → aspect-fit gives rendered 250x500,
    // letterboxed horizontally with 125pt bars on each side.
    func testCenterMapsToDeviceCenter() {
        let p = viewPointToDevicePoint(.init(x: 250, y: 250),
                                       viewSize: .init(width: 500, height: 500),
                                       deviceSize: .init(width: 1000, height: 2000))
        XCTAssertEqual(p.x, 500, accuracy: 0.5)
        XCTAssertEqual(p.y, 1000, accuracy: 0.5)
    }

    func testClickInLetterboxClampsToEdge() {
        // x=10 is inside the left letterbox bar (bar is 0..125) → clamps to device x 0.
        let p = viewPointToDevicePoint(.init(x: 10, y: 250),
                                       viewSize: .init(width: 500, height: 500),
                                       deviceSize: .init(width: 1000, height: 2000))
        XCTAssertEqual(p.x, 0, accuracy: 0.5)
    }

    func testTopLeftOfImage() {
        // Rendered image left edge is at view x=125, top at y=0.
        let p = viewPointToDevicePoint(.init(x: 125, y: 0),
                                       viewSize: .init(width: 500, height: 500),
                                       deviceSize: .init(width: 1000, height: 2000))
        XCTAssertEqual(p.x, 0, accuracy: 0.5)
        XCTAssertEqual(p.y, 0, accuracy: 0.5)
    }

    func testDegenerateSizesReturnZero() {
        let p = viewPointToDevicePoint(.init(x: 5, y: 5),
                                       viewSize: .zero,
                                       deviceSize: .init(width: 1000, height: 2000))
        XCTAssertEqual(p, .zero)
    }
}
