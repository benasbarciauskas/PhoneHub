import XCTest
@testable import PhoneHubCore

final class ApiAgentRuntimeTests: XCTestCase {
    func testMCPLaunchConfigurationReusesAutomationPlanArguments() throws {
        let device = Device(id: "ios-device", platform: .ios, model: "iPhone",
                            osVersion: "18", status: "connected")
        let preset = Preset(name: "Test", goal: "Open Settings", platforms: [.ios])
        let plan = try buildAutomationPlan(preset: preset, device: device)

        XCTAssertEqual(
            try ApiAgentRuntime.mcpLaunchConfiguration(plan: plan),
            McpLaunchConfiguration(
                command: "npx",
                arguments: ["-y", "mirroir-mcp", "--dangerously-skip-permissions"]
            )
        )
    }

    func testPhoneToolDefinitionsContainRequiredMinimalSet() throws {
        let tools = phoneControlTools(serverName: "mirroir")
        XCTAssertEqual(Set(tools.map(\.name)), Set([
            "launch_app", "tap", "type_text", "swipe", "press_home", "press_back",
            "press_app_switcher", "scroll_to", "describe_screen", "open_url"
        ]))
        let tap = try XCTUnwrap(tools.first { $0.name == "tap" })
        let schema = try json(tap.parametersJSON)
        XCTAssertEqual(schema["required"] as? [String], ["x", "y"])
    }

    func testAndroidToolsRequireSerialForEveryCall() throws {
        for tool in phoneControlTools(serverName: "androir") {
            let schema = try json(tool.parametersJSON)
            let required = try XCTUnwrap(schema["required"] as? [String])
            XCTAssertTrue(required.contains("serial"), tool.name)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertNotNil(properties["serial"], tool.name)
        }
    }

    func testDecisionRecognizesNeedInputToolsAndCompletion() {
        XCTAssertEqual(
            ApiAgentRuntime.decision(for: LLMResponse(text: "NEED_INPUT: Which account?", toolCalls: [])),
            .needInput("Which account?")
        )
        let call = LLMToolCall(id: "1", name: "tap", argumentsJSON: #"{"x":1,"y":2}"#)
        XCTAssertEqual(ApiAgentRuntime.decision(for: LLMResponse(text: nil, toolCalls: [call])),
                       .callTools)
        XCTAssertEqual(ApiAgentRuntime.decision(for: LLMResponse(text: "Done", toolCalls: [])),
                       .complete("Done"))
    }

    func testRuntimeExecutesToolAndReturnsFinalTextWithSharedEvents() async {
        let call = LLMToolCall(id: "call_1", name: "tap", argumentsJSON: #"{"x":12,"y":34}"#)
        let provider = SequenceProvider([
            LLMResponse(text: nil, toolCalls: [call]),
            LLMResponse(text: "Done.", toolCalls: [])
        ])
        let client = RecordingMCPClient(result: McpToolResult(text: "Tapped", isError: false))
        let runtime = ApiAgentRuntime(provider: provider, client: client)
        let events = EventRecorder()

        let result = await runtime.run(
            systemPreamble: "system", prompt: "goal", priorMessages: [],
            maxToolCalls: 4, serverName: "mirroir", onEvent: { events.append($0) }
        )

        XCTAssertEqual(result.outcome, .completed("Done."))
        XCTAssertEqual(client.calls.map(\.name), ["tap"])
        XCTAssertEqual(client.calls.first?.arguments["x"] as? Int, 12)
        XCTAssertEqual(events.values, [
            .toolUse(name: "tap", summary: "x=12 y=34", rawInput: #"{"x":12,"y":34}"#),
            .toolResult("Tapped"),
            .assistantText("Done."),
            .result(subtype: "success", text: nil, sessionId: nil)
        ])
        XCTAssertTrue(client.started)
        XCTAssertTrue(client.stopped)
    }

    func testRuntimeStopsForNeedInputWithoutCallingTools() async {
        let provider = SequenceProvider([LLMResponse(text: "NEED_INPUT: Log in first?", toolCalls: [])])
        let client = RecordingMCPClient(result: McpToolResult(text: "", isError: false))
        let runtime = ApiAgentRuntime(provider: provider, client: client)
        let events = EventRecorder()

        let result = await runtime.run(
            systemPreamble: "system", prompt: "goal", priorMessages: [],
            maxToolCalls: 2, serverName: "mirroir", onEvent: { events.append($0) }
        )

        XCTAssertEqual(result.outcome, .needsInput("Log in first?"))
        XCTAssertEqual(result.messages.last,
                       LLMMessage(role: .assistant, content: "NEED_INPUT: Log in first?"))
        XCTAssertEqual(events.values, [.needInput(question: "Log in first?")])
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testRuntimeRejectsInvalidArgumentsAndHonorsToolCap() async {
        let invalidProvider = SequenceProvider([
            LLMResponse(text: nil, toolCalls: [
                LLMToolCall(id: "bad", name: "tap", argumentsJSON: "[]")
            ])
        ])
        let invalidClient = RecordingMCPClient(result: McpToolResult(text: "", isError: false))
        let invalidEvents = EventRecorder()
        let invalidResult = await ApiAgentRuntime(provider: invalidProvider, client: invalidClient).run(
            systemPreamble: "system", prompt: "goal", priorMessages: [],
            maxToolCalls: 2, serverName: "mirroir", onEvent: { invalidEvents.append($0) }
        )
        XCTAssertEqual(invalidResult.outcome, .failed("The model returned invalid tool arguments."))
        XCTAssertTrue(invalidClient.calls.isEmpty)

        let calls = [
            LLMToolCall(id: "1", name: "press_home", argumentsJSON: "{}"),
            LLMToolCall(id: "2", name: "press_back", argumentsJSON: "{}")
        ]
        let cappedProvider = SequenceProvider([LLMResponse(text: nil, toolCalls: calls)])
        let cappedClient = RecordingMCPClient(result: McpToolResult(text: "ok", isError: false))
        let cappedResult = await ApiAgentRuntime(provider: cappedProvider, client: cappedClient).run(
            systemPreamble: "system", prompt: "goal", priorMessages: [],
            maxToolCalls: 1, serverName: "mirroir", onEvent: { _ in }
        )
        XCTAssertEqual(cappedResult.outcome, .maxStepsReached)
        XCTAssertEqual(cappedClient.calls.map(\.name), ["press_home"])
    }

    func testRuntimeNeverEmitsSensitiveValuesFromProviderErrors() async {
        let secret = "phonehub-test-secret-never-log"
        let provider = FailingProvider(error: SecretError(message: "Rejected \(secret)"))
        let client = RecordingMCPClient(result: McpToolResult(text: "", isError: false))
        let events = EventRecorder()
        let runtime = ApiAgentRuntime(provider: provider, client: client,
                                      sensitiveValues: [secret])

        let outcome = await runtime.run(
            systemPreamble: "system", prompt: "goal", priorMessages: [],
            maxToolCalls: 2, serverName: "mirroir", onEvent: { events.append($0) }
        )

        let rendered = String(describing: events.values)
        XCTAssertFalse(rendered.contains(secret))
        XCTAssertFalse(String(describing: outcome).contains(secret))
        XCTAssertEqual(events.values, [
            .result(subtype: "error", text: "The LLM provider request failed.", sessionId: nil)
        ])
    }

    func testVisionOnAttachesScreenshotImageToProviderMessages() async throws {
        let provider = CapturingProvider([
            LLMResponse(text: "Looks like Settings.", toolCalls: [])
        ])
        let client = MapMCPClient(results: [
            "screenshot": McpToolResult(
                text: "", isError: false,
                imageBase64: Self.tinyPNGBase64, imageMediaType: "image/png"
            ),
            "describe_screen": McpToolResult(
                text: #"- "Settings" button at (209, 100)"#, isError: false
            )
        ])
        let events = EventRecorder()
        let runtime = ApiAgentRuntime(provider: provider, client: client, vision: true)

        let result = await runtime.run(
            systemPreamble: "system", prompt: "open wifi", priorMessages: [],
            maxToolCalls: 2, serverName: "mirroir", onEvent: { events.append($0) }
        )

        XCTAssertEqual(result.outcome, .completed("Looks like Settings."))
        let sent = await provider.firstMessages()
        let visionMessage = try XCTUnwrap(sent.last)
        XCTAssertEqual(visionMessage.role, .user)
        XCTAssertEqual(visionMessage.image?.base64, Self.tinyPNGBase64)
        XCTAssertEqual(visionMessage.image?.mediaType, "image/png")
        XCTAssertTrue(visionMessage.content?.contains("[1] Settings") == true)
        // Vision frames are ephemeral — not in returned transcript.
        XCTAssertTrue(result.messages.allSatisfy { $0.image == nil })
        XCTAssertEqual(client.calls.map(\.name), ["screenshot", "describe_screen"])
        XCTAssertTrue(events.values.contains(.toolUse(
            name: "screenshot", summary: "vision capture", rawInput: "{}"
        )))
        XCTAssertTrue(events.values.contains(.toolResult("[image captured]")))
        // Never log base64 image bytes.
        XCTAssertFalse(String(describing: events.values).contains(Self.tinyPNGBase64))
    }

    func testVisionOffDoesNotCallScreenshotOrAttachImage() async {
        let provider = CapturingProvider([
            LLMResponse(text: "Done.", toolCalls: [])
        ])
        let client = MapMCPClient(results: [:])
        let runtime = ApiAgentRuntime(provider: provider, client: client, vision: false)

        let result = await runtime.run(
            systemPreamble: "system", prompt: "goal", priorMessages: [],
            maxToolCalls: 2, serverName: "mirroir", onEvent: { _ in }
        )

        XCTAssertEqual(result.outcome, .completed("Done."))
        XCTAssertTrue(client.calls.isEmpty)
        let sent = await provider.firstMessages()
        XCTAssertTrue(sent.allSatisfy { $0.image == nil })
    }

    /// 1×1 PNG fixture — tests only.
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    private func json(_ string: String) throws -> [String: Any] {
        let data = try XCTUnwrap(string.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private struct SecretError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct FailingProvider: LLMProvider {
    let error: any Error
    func send(messages: [LLMMessage], tools: [LLMToolDefinition]) async throws -> LLMResponse {
        throw error
    }
}

private actor SequenceProvider: LLMProvider {
    private var responses: [LLMResponse]

    init(_ responses: [LLMResponse]) { self.responses = responses }

    func send(messages: [LLMMessage], tools: [LLMToolDefinition]) async throws -> LLMResponse {
        guard !responses.isEmpty else { throw LLMProviderError.invalidResponse }
        return responses.removeFirst()
    }
}

private actor CapturingProvider: LLMProvider {
    private var responses: [LLMResponse]
    private var received: [[LLMMessage]] = []

    init(_ responses: [LLMResponse]) { self.responses = responses }

    func send(messages: [LLMMessage], tools: [LLMToolDefinition]) async throws -> LLMResponse {
        received.append(messages)
        guard !responses.isEmpty else { throw LLMProviderError.invalidResponse }
        return responses.removeFirst()
    }

    func firstMessages() -> [LLMMessage] { received.first ?? [] }
}

private final class RecordingMCPClient: McpToolClient, @unchecked Sendable {
    struct Call { let name: String; let arguments: [String: Any] }
    private(set) var started = false
    private(set) var stopped = false
    private(set) var calls: [Call] = []
    private let result: McpToolResult

    init(result: McpToolResult) { self.result = result }
    func start() async throws { started = true }
    func callTool(_ name: String, arguments: [String: Any],
                  timeoutSeconds: Double) async throws -> McpToolResult {
        calls.append(Call(name: name, arguments: arguments))
        return result
    }
    func stop() { stopped = true }
}

private final class MapMCPClient: McpToolClient, @unchecked Sendable {
    struct Call { let name: String; let arguments: [String: Any] }
    private(set) var started = false
    private(set) var stopped = false
    private(set) var calls: [Call] = []
    private let results: [String: McpToolResult]

    init(results: [String: McpToolResult]) { self.results = results }
    func start() async throws { started = true }
    func callTool(_ name: String, arguments: [String: Any],
                  timeoutSeconds: Double) async throws -> McpToolResult {
        calls.append(Call(name: name, arguments: arguments))
        return results[name] ?? McpToolResult(text: "", isError: false)
    }
    func stop() { stopped = true }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StreamEvent] = []
    var values: [StreamEvent] { lock.withLock { storage } }
    func append(_ event: StreamEvent) { lock.withLock { storage.append(event) } }
}
