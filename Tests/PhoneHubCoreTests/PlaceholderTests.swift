import XCTest
@testable import PhoneHubCore

final class PlaceholderTests: XCTestCase {
    func testDeviceIsReady() {
        let d = Device(id: "x", platform: .android, model: "m", osVersion: "14", status: "device")
        XCTAssertTrue(d.isReady)
    }
}
