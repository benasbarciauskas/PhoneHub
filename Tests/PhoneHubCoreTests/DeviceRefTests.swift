import XCTest
@testable import PhoneHubCore

final class DeviceRefTests: XCTestCase {
    private let iphone = Device(id: "udid-a", platform: .ios, model: "iPhone 15 Pro",
                                osVersion: "18.0", status: "device")
    private let pixel = Device(id: "serial-b", platform: .android, model: "Pixel 8",
                               osVersion: "14", status: "device")

    func testMatchByModel() {
        let found = resolveDeviceRef("Pixel 8", devices: [iphone, pixel])
        XCTAssertEqual(found?.id, pixel.id)
    }

    func testNoMatch() {
        XCTAssertNil(resolveDeviceRef("Galaxy S24", devices: [iphone, pixel]))
        XCTAssertNil(resolveDeviceRef("", devices: [iphone]))
        XCTAssertNil(resolveDeviceRef("   ", devices: [iphone]))
    }

    func testCaseInsensitiveModelMatch() {
        let found = resolveDeviceRef("iphone 15 pro", devices: [iphone, pixel])
        XCTAssertEqual(found?.id, iphone.id)
        XCTAssertEqual(resolveDeviceRef("PIXEL 8", devices: [iphone, pixel])?.id, pixel.id)
    }

    func testExactLabelFallback() {
        let labels = [iphone.id: "Ben's phone"]
        XCTAssertEqual(resolveDeviceRef("Ben's phone", devices: [iphone, pixel], labels: labels)?.id,
                       iphone.id)
        // Model still wins over label when both could apply.
        XCTAssertEqual(resolveDeviceRef("iPhone 15 Pro", devices: [iphone], labels: labels)?.id,
                       iphone.id)
        // Label match is exact (not case-insensitive).
        XCTAssertNil(resolveDeviceRef("ben's phone", devices: [iphone], labels: labels))
    }
}
