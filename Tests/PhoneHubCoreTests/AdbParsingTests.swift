import XCTest
@testable import PhoneHubCore

final class AdbParsingTests: XCTestCase {
    func testParseDevicesNormal() {
        let out = """
        List of devices attached
        emulator-5554\tdevice product:sdk model:Pixel_6 device:generic
        R3CT90\tunauthorized
        ZY223\toffline

        """
        let rows = parseAdbDevices(out)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].serial, "emulator-5554")
        XCTAssertEqual(rows[0].state, "device")
        XCTAssertEqual(rows[1].state, "unauthorized")
        XCTAssertEqual(rows[2].state, "offline")
    }

    func testParseDevicesEmpty() {
        let rows = parseAdbDevices("List of devices attached\n\n")
        XCTAssertTrue(rows.isEmpty)
    }

    func testParseDevicesSkipsDaemonChatter() {
        let out = """
        * daemon not running; starting now at tcp:5037 *
        * daemon started successfully *
        List of devices attached
        ZY223JR9XN\tdevice
        """
        let rows = parseAdbDevices(out)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].serial, "ZY223JR9XN")
    }

}
