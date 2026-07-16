import XCTest
@testable import PhoneHubCore

final class CondensePromptTests: XCTestCase {
    func testPromptIncludesGoalRawStepsAndStrictSchema() throws {
        let step = AutomationStep.pressHome(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let prompt = try CondensePrompt.prompt(goal: "Return home", rawSteps: [step])
        XCTAssertTrue(prompt.contains("Return home"))
        XCTAssertTrue(prompt.contains(#""type" : "pressHome""#))
        XCTAssertTrue(prompt.contains("ONLY the JSON array"))
        XCTAssertTrue(prompt.contains("launchApp|tap|doubleTap|longPress"))
    }

    func testBackendArgumentsAreTextOnly() throws {
        let prompt = "strict prompt"
        XCTAssertEqual(CondensePrompt.arguments(prompt: prompt, backend: .claude),
                       ["-p", prompt, "--output-format", "text"])
        let codex = CondensePrompt.arguments(prompt: prompt, backend: .codex)
        XCTAssertEqual(codex.last, prompt)
        XCTAssertTrue(codex.contains("exec"))
        XCTAssertFalse(codex.contains("--json"))
        for backend in [AgentBackend.openrouter, .openai, .anthropic] {
            XCTAssertEqual(CondensePrompt.arguments(prompt: prompt, backend: backend), [])
        }
    }

    func testParsesValidStepArray() throws {
        let expected: [AutomationStep] = [
            .launchApp(id: UUID(), name: "Settings"),
            .tap(id: UUID(), label: "General", x: nil, y: nil)
        ]
        let data = try JSONEncoder().encode(expected)
        XCTAssertEqual(try CondensePrompt.parseResponse(String(decoding: data, as: UTF8.self)), expected)
    }

    func testRejectsGarbageAndUnknownStepType() {
        XCTAssertThrowsError(try CondensePrompt.parseResponse("Here is the result: []"))
        let unknown = #"[{"type":"future","id":"00000000-0000-0000-0000-000000000001"}]"#
        XCTAssertThrowsError(try CondensePrompt.parseResponse(unknown))
    }

    func testDescriptionPromptIncludesRawStepsAndRequestsShortPlainLanguage() throws {
        let step = AutomationStep.typeText(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            text: "hello"
        )

        let prompt = try CondensePrompt.descriptionPrompt(rawSteps: [step])

        XCTAssertTrue(prompt.contains(#""type" : "typeText""#))
        XCTAssertTrue(prompt.contains("4-12 words"))
        XCTAssertTrue(prompt.contains("plain text"))
    }

    func testParsesTrimmedRecordingDescriptionAndRejectsEmpty() throws {
        XCTAssertEqual(
            try CondensePrompt.parseDescription("  \"Search for a contact\"  \n"),
            "Search for a contact"
        )
        XCTAssertThrowsError(try CondensePrompt.parseDescription(" \n "))
    }
}
