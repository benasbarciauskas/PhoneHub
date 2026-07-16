import XCTest
@testable import PhoneHubCore

final class McpDirectClientTests: XCTestCase {
    func testEncodeRequestIsNewlineDelimitedJSONRPC() throws {
        let data = try McpDirectClient.encodeRequest(
            method: "initialize",
            params: ["protocolVersion": "2024-11-05"],
            id: 7
        )
        XCTAssertEqual(data.last, Character("\n").asciiValue)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any])
        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(object["method"] as? String, "initialize")
        XCTAssertEqual(object["id"] as? Int, 7)
    }

    func testDecodeResponseFiltersUnrelatedID() throws {
        let line = #"{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":"2024-11-05"}}"#
        XCTAssertNil(try McpDirectClient.decodeResponse(line: line, expectedID: 1))
        XCTAssertNotNil(try McpDirectClient.decodeResponse(line: line, expectedID: 2))
    }

    func testExtractToolSuccessConcatenatesText() throws {
        let json: [String: Any] = ["result": [
            "content": [["type": "text", "text": "first"], ["type": "text", "text": "second"]],
            "isError": false
        ]]
        XCTAssertEqual(try McpDirectClient.extractToolResult(json: json),
                       McpToolResult(text: "first\nsecond", isError: false))
    }

    func testExtractToolError() throws {
        let json: [String: Any] = ["result": [
            "content": [["type": "text", "text": "not connected"]],
            "isError": true
        ]]
        XCTAssertEqual(try McpDirectClient.extractToolResult(json: json),
                       McpToolResult(text: "not connected", isError: true))
    }

    func testExtractToolResultPullsImageContentBlocks() throws {
        let json: [String: Any] = ["result": [
            "content": [
                ["type": "text", "text": "ok"],
                ["type": "image", "mimeType": "image/png", "data": "abc123"]
            ],
            "isError": false
        ]]
        let result = try McpDirectClient.extractToolResult(json: json)
        XCTAssertEqual(result.text, "ok")
        XCTAssertEqual(result.imageBase64, "abc123")
        XCTAssertEqual(result.imageMediaType, "image/png")
        XCTAssertFalse(result.isError)
    }

    func testLiveMirroirStatusWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PHONEHUB_LIVE_MCP"] == "1" else {
            throw XCTSkip("Set PHONEHUB_LIVE_MCP=1 to run")
        }
        let client = McpDirectClient(command: "/usr/bin/env",
                                     arguments: ["npx", "-y", "mirroir-mcp", "--dangerously-skip-permissions"])
        try await client.start()
        defer { client.stop() }
        let result = try await client.callTool("status", arguments: [:], timeoutSeconds: 20)
        XCTAssertFalse(result.isError)
    }
}
