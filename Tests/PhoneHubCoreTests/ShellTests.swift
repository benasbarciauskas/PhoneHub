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

    func testValidHostPortAcceptsIPAndHostname() {
        XCTAssertTrue(isValidHostPort("192.168.1.50:5555"))
        XCTAssertTrue(isValidHostPort("hostname:5555"))
        XCTAssertTrue(isValidHostPort("pixel-6.local:5555"))
        XCTAssertTrue(isValidHostPort("10.0.0.1:1"))
        XCTAssertTrue(isValidHostPort("host:65535"))
    }

    func testValidHostPortRejectsInjectionMissingPortAndSpaces() {
        XCTAssertFalse(isValidHostPort("192.168.1.50:5555;rm -rf /"))
        XCTAssertFalse(isValidHostPort("192.168.1.50:5555|cat"))
        XCTAssertFalse(isValidHostPort("host:$(id)"))
        XCTAssertFalse(isValidHostPort("host;`id`"))
        XCTAssertFalse(isValidHostPort("192.168.1.50"))
        XCTAssertFalse(isValidHostPort(":5555"))
        XCTAssertFalse(isValidHostPort("host:"))
        XCTAssertFalse(isValidHostPort("192.168.1.50 5555"))
        XCTAssertFalse(isValidHostPort("host :5555"))
        XCTAssertFalse(isValidHostPort("host:port"))
        XCTAssertFalse(isValidHostPort("host:0"))
        XCTAssertFalse(isValidHostPort("host:65536"))
        XCTAssertFalse(isValidHostPort(""))
        XCTAssertFalse(isValidHostPort("a b:5555"))
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
