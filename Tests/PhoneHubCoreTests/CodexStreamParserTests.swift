import XCTest
@testable import PhoneHubCore

final class CodexStreamParserTests: XCTestCase {
    func testParsesCapturedCodexJSONLFixtures() {
        let fixtures: [(String, StreamEvent)] = [
            (#"{"type":"thread.started","thread_id":"019f67d3-4385-78d0-bc7f-1ef4a7cb0de5"}"#,
             .system(subtype: "init", sessionId: "019f67d3-4385-78d0-bc7f-1ef4a7cb0de5")),
            (#"{"type":"turn.started"}"#, .ignored),
            (#"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}"#,
             .assistantText("OK")),
            (#"{"type":"item.started","item":{"id":"item_1","type":"mcp_tool_call","server":"mirroir","tool":"status","arguments":{},"result":null,"error":null,"status":"in_progress"}}"#,
             .toolUse(name: "status", summary: "", rawInput: "{}")),
            (#"{"type":"item.completed","item":{"id":"item_1","type":"mcp_tool_call","server":"mirroir","tool":"status","arguments":{},"result":{"content":[{"type":"text","text":"Connected — mirroring active"}],"structured_content":null},"error":null,"status":"completed"}}"#,
             .toolResult("Connected — mirroring active")),
            (#"{"type":"turn.completed","usage":{"input_tokens":21820,"cached_input_tokens":9984,"output_tokens":5,"reasoning_output_tokens":0}}"#,
             .result(subtype: "success", text: nil, sessionId: nil))
        ]

        for (line, expected) in fixtures {
            XCTAssertEqual(CodexStreamParser.parseLine(line), expected, line)
        }
    }

    func testDetectsNeedInputInCompletedAgentMessage() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"I need help.\nNEED_INPUT: Which account?"}}"#
        XCTAssertEqual(CodexStreamParser.parseLine(line),
                       .needInput(question: "Which account?"))
    }

    func testSummarizesMCPArguments() {
        let line = #"{"type":"item.started","item":{"type":"mcp_tool_call","server":"androir","tool":"tap","arguments":{"serial":"ABC123","x":12,"y":34},"status":"in_progress"}}"#
        XCTAssertEqual(CodexStreamParser.parseLine(line),
                       .toolUse(name: "tap", summary: "serial=ABC123 x=12 y=34",
                                rawInput: #"{"serial":"ABC123","x":12,"y":34}"#))
    }

    func testMapsMCPErrorAndFailedTurn() {
        let toolError = #"{"type":"item.completed","item":{"type":"mcp_tool_call","server":"mirroir","tool":"tap","arguments":{},"result":null,"error":{"message":"device offline"},"status":"failed"}}"#
        XCTAssertEqual(CodexStreamParser.parseLine(toolError), .toolResult("device offline"))

        let turnFailed = #"{"type":"turn.failed","error":{"message":"model unavailable"}}"#
        XCTAssertEqual(CodexStreamParser.parseLine(turnFailed),
                       .result(subtype: "error", text: "model unavailable", sessionId: nil))
    }

    func testIgnoresMalformedAndUnknownEvents() {
        XCTAssertEqual(CodexStreamParser.parseLine("not json"), .ignored)
        XCTAssertEqual(CodexStreamParser.parseLine(#"{"type":"reasoning"}"#), .ignored)
    }

    func testSharedParserDispatchesByBackend() {
        let codex = #"{"type":"thread.started","thread_id":"codex-session"}"#
        XCTAssertEqual(parseStreamLine(codex, backend: .codex),
                       .system(subtype: "init", sessionId: "codex-session"))

        let claude = #"{"type":"system","subtype":"init","session_id":"claude-session"}"#
        XCTAssertEqual(parseStreamLine(claude, backend: .claude),
                       .system(subtype: "init", sessionId: "claude-session"))
    }
}
