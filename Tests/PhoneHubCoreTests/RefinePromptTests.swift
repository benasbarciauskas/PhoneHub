import XCTest
@testable import PhoneHubCore

final class RefinePromptTests: XCTestCase {

    func testPromptKeepsUserTextAndInstruction() {
        let prompt = RefinePrompt.prompt(for: "open ig and like 3 posts")
        // The rewrite instruction is present.
        XCTAssertTrue(prompt.contains("Rewrite this into a single clear, concrete instruction"))
        XCTAssertTrue(prompt.contains("Keep the user's intent."))
        XCTAssertTrue(prompt.contains("Output only the rewritten instruction."))
        // The raw user text is appended verbatim.
        XCTAssertTrue(prompt.contains("open ig and like 3 posts"))
        // Instruction comes before the user text.
        let iRange = prompt.range(of: "Rewrite this")!
        let uRange = prompt.range(of: "open ig")!
        XCTAssertTrue(iRange.lowerBound < uRange.lowerBound)
    }

    func testArgumentsAreTextOnlyNoTools() {
        let args = RefinePrompt.arguments(for: "scroll tiktok")
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("text"))
        // Text-only: no tools, no mcp-config, no stream-json.
        XCTAssertFalse(args.contains("--mcp-config"))
        XCTAssertFalse(args.contains("--allowedTools"))
        XCTAssertFalse(args.contains("stream-json"))
        XCTAssertFalse(args.contains("--dangerously-skip-permissions"))
    }
}
