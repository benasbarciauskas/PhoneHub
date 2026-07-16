import XCTest
@testable import PhoneHubCore

final class VisionCaptureTests: XCTestCase {
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    func testFormatElementListUsesNumberedCoords() {
        let text = """
        - "Settings" button at (209, 100)
        - "Wi-Fi" cell at (209, 260)
        """
        let formatted = VisionCapture.formatElementList(text)
        XCTAssertEqual(
            formatted,
            "On-screen elements: [1] Settings (209,100) [2] Wi-Fi (209,260)"
        )
    }

    func testImageContentFromInlineBase64() {
        let result = McpToolResult(
            text: "", isError: false,
            imageBase64: Self.tinyPNGBase64, imageMediaType: "image/png"
        )
        let image = VisionCapture.imageContent(from: result)
        XCTAssertEqual(image?.base64, Self.tinyPNGBase64)
        XCTAssertEqual(image?.mediaType, "image/png")
    }

    func testImageContentFromFilePathReadsBytes() {
        let dir = FileManager.default.temporaryDirectory
        let path = dir.appendingPathComponent("vision-fixture-\(UUID().uuidString).png").path
        let data = Data(base64Encoded: Self.tinyPNGBase64)!
        FileManager.default.createFile(atPath: path, contents: data)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = McpToolResult(text: path, isError: false)
        let image = VisionCapture.imageContent(from: result)
        XCTAssertEqual(image?.base64, Self.tinyPNGBase64)
        XCTAssertEqual(image?.mediaType, "image/png")
    }

    func testScreenshotLogSummaryNeverIncludesBase64() {
        let result = McpToolResult(
            text: "", isError: false,
            imageBase64: Self.tinyPNGBase64, imageMediaType: "image/png"
        )
        let summary = VisionCapture.screenshotLogSummary(for: result)
        XCTAssertEqual(summary, "[image captured]")
        XCTAssertFalse(summary.contains(Self.tinyPNGBase64))
    }
}
