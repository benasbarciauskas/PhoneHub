import XCTest
@testable import PhoneHubCore

final class ShellTests: XCTestCase {
    func testAdbArgsPrependsSerial() {
        XCTAssertEqual(adbArgs(serial: "ZY223", "shell", "input", "tap", "10", "20"),
                       ["-s", "ZY223", "shell", "input", "tap", "10", "20"])
    }

    func testValidSerialRejectsInjection() {
        XCTAssertTrue(isValidSerial("emulator-5554"))
        XCTAssertTrue(isValidSerial("ZY223JR9XN"))
        XCTAssertFalse(isValidSerial("a b"))
        XCTAssertFalse(isValidSerial("a;rm -rf"))
        XCTAssertFalse(isValidSerial(""))
    }

    func testRunToolDrainsLargeStderrWhileReadingStdout() throws {
        guard resolveTool("perl") != nil else {
            throw XCTSkip("perl is required for stderr drain regression test")
        }

        let result = try runTool(
            "perl",
            ["-e", "print STDERR \"x\" x (1024 * 1024); print STDOUT \"ok\";"],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "ok")
        XCTAssertEqual(result.stderr.count, 1024 * 1024)
    }
}
