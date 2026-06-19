import XCTest
@testable import PhoneHubCore

final class ShellTests: XCTestCase {
    func testAdbArgsPrependsSerial() {
        XCTAssertEqual(adbArgs(serial: "ZY223", "shell", "input", "tap", "10", "20"),
                       ["-s", "ZY223", "shell", "input", "tap", "10", "20"])
    }

    func testTapArgs() {
        XCTAssertEqual(adbTapArgs(serial: "ZY223", x: 540, y: 1170),
                       ["-s", "ZY223", "shell", "input", "tap", "540", "1170"])
    }

    func testScreencapArgs() {
        XCTAssertEqual(adbScreencapArgs(serial: "ZY223"),
                       ["-s", "ZY223", "exec-out", "screencap", "-p"])
    }

    func testValidSerialRejectsInjection() {
        XCTAssertTrue(isValidSerial("emulator-5554"))
        XCTAssertTrue(isValidSerial("ZY223JR9XN"))
        XCTAssertFalse(isValidSerial("a b"))
        XCTAssertFalse(isValidSerial("a;rm -rf"))
        XCTAssertFalse(isValidSerial(""))
    }
}
