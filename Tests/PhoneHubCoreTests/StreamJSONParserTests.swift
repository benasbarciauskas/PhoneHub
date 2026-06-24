import XCTest
@testable import PhoneHubCore

final class StreamJSONParserTests: XCTestCase {

    private func fixtureLines() throws -> [String] {
        // Fixture lives next to this test file.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = dir.appendingPathComponent("Fixtures/stream-sample.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }

    func testParsesSystemInit() {
        let event = StreamJSONParser.parseLine(
            #"{"type":"system","subtype":"init","tools":[]}"#)
        XCTAssertEqual(event, .system(subtype: "init", sessionId: nil))
        XCTAssertNil(StreamJSONParser.update(for: event)) // system is dropped
    }

    func testParsesSessionIdFromInit() {
        let event = StreamJSONParser.parseLine(
            #"{"type":"system","subtype":"init","session_id":"abc-123-uuid","tools":[]}"#)
        XCTAssertEqual(event, .system(subtype: "init", sessionId: "abc-123-uuid"))
        guard case let .system(_, sessionId) = event else { return XCTFail("not system") }
        XCTAssertEqual(sessionId, "abc-123-uuid")
    }

    func testDetectsNeedInputAssistantLine() {
        let event = StreamJSONParser.parseLine(
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"NEED_INPUT: What is the 2FA code?"}]}}"#)
        XCTAssertEqual(event, .needInput(question: "What is the 2FA code?"))
        let update = StreamJSONParser.update(for: event)
        XCTAssertEqual(update?.currentAction, "Needs input")
        XCTAssertTrue(update?.logLine?.contains("What is the 2FA code?") ?? false)
    }

    func testDetectNeedInputPureHelper() {
        XCTAssertEqual(StreamJSONParser.detectNeedInput("NEED_INPUT: pick an account"), "pick an account")
        // Marker can appear after a preamble line.
        XCTAssertEqual(
            StreamJSONParser.detectNeedInput("I'm blocked by a login wall.\nNEED_INPUT: which login?"),
            "which login?")
        // Case-insensitive marker.
        XCTAssertEqual(StreamJSONParser.detectNeedInput("need_input: hi"), "hi")
        // Not a marker mid-sentence.
        XCTAssertNil(StreamJSONParser.detectNeedInput("This is not a NEED_INPUT: trap"))
        XCTAssertNil(StreamJSONParser.detectNeedInput("just normal text"))
        // Empty question is ignored.
        XCTAssertNil(StreamJSONParser.detectNeedInput("NEED_INPUT:   "))
    }

    func testParsesAssistantText() {
        let event = StreamJSONParser.parseLine(
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Opening Instagram."}]}}"#)
        XCTAssertEqual(event, .assistantText("Opening Instagram."))
        XCTAssertEqual(StreamJSONParser.update(for: event)?.logLine, "Opening Instagram.")
    }

    func testParsesToolUseAndStripsPrefix() {
        let event = StreamJSONParser.parseLine(
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"mcp__mirroir__tap","input":{"x":120,"y":340}}]}}"#)
        guard case let .toolUse(name, summary) = event else { return XCTFail("not toolUse") }
        XCTAssertEqual(name, "tap")
        XCTAssertTrue(summary.contains("x=120"))
        let update = StreamJSONParser.update(for: event)
        XCTAssertEqual(update?.currentAction, "tap x=120 y=340")
    }

    func testParsesSuccessResult() {
        let event = StreamJSONParser.parseLine(
            #"{"type":"result","subtype":"success","result":"Done it."}"#)
        XCTAssertEqual(event, .result(subtype: "success", text: "Done it."))
        let update = StreamJSONParser.update(for: event)
        XCTAssertEqual(update?.finished, true)
        XCTAssertEqual(update?.failed, false)
        XCTAssertEqual(update?.logLine, "Done it.")
    }

    func testParsesErrorResult() {
        let event = StreamJSONParser.parseLine(
            #"{"type":"result","subtype":"error_max_turns"}"#)
        let update = StreamJSONParser.update(for: event)
        XCTAssertEqual(update?.finished, true)
        XCTAssertEqual(update?.failed, true)
    }

    func testIgnoresNonJSONLine() {
        XCTAssertEqual(StreamJSONParser.parseLine("not json at all"), .ignored)
        XCTAssertEqual(StreamJSONParser.parseLine(""), .ignored)
        XCTAssertNil(StreamJSONParser.update(for: .ignored))
    }

    func testParsesFullFixtureStream() throws {
        let lines = try fixtureLines()
        var logLines: [String] = []
        var lastAction: String?
        var finished = false
        var failed = false
        for line in lines {
            let event = StreamJSONParser.parseLine(line)
            guard let update = StreamJSONParser.update(for: event) else { continue }
            if let l = update.logLine { logLines.append(l) }
            if let a = update.currentAction { lastAction = a }
            if update.finished { finished = true; failed = update.failed }
        }
        // text + 2 tool uses + result = 4 log lines surfaced.
        XCTAssertEqual(logLines.count, 4)
        XCTAssertTrue(logLines.contains("Opening Instagram now."))
        XCTAssertTrue(logLines.contains { $0.contains("launch_app") })
        XCTAssertEqual(lastAction, "Finished")
        XCTAssertTrue(finished)
        XCTAssertFalse(failed)
    }
}
