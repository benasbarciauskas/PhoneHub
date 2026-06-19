import XCTest
@testable import PhoneHubCore

final class ScrcpyControllerTests: XCTestCase {
    func testScrcpyArgsBuildsWindowAndSerialFlags() throws {
        let args = try scrcpyArgs(serial: "emulator-5554",
                                  x: 11,
                                  y: 22,
                                  width: 333,
                                  height: 444,
                                  title: "PhoneHub Pixel")

        XCTAssertTrue(args.contains("--window-borderless"))
        XCTAssertFlag(args, "--window-x", hasValue: "11")
        XCTAssertFlag(args, "--window-y", hasValue: "22")
        XCTAssertFlag(args, "--window-width", hasValue: "333")
        XCTAssertFlag(args, "--window-height", hasValue: "444")
        XCTAssertFlag(args, "--window-title", hasValue: "PhoneHub Pixel")
        XCTAssertFlag(args, "-s", hasValue: "emulator-5554")
    }

    func testScrcpyArgsRejectsInvalidSerial() {
        XCTAssertThrowsError(try scrcpyArgs(serial: "bad serial;rm",
                                           x: 0,
                                           y: 0,
                                           width: 100,
                                           height: 100,
                                           title: "PhoneHub")) { error in
            XCTAssertEqual(error as? ScrcpyArgsError, .invalidSerial)
        }
    }

    private func XCTAssertFlag(_ args: [String],
                               _ flag: String,
                               hasValue expected: String,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        guard let index = args.firstIndex(of: flag), index + 1 < args.endIndex else {
            return XCTFail("Missing \(flag)", file: file, line: line)
        }
        XCTAssertEqual(args[index + 1], expected, file: file, line: line)
    }
}
