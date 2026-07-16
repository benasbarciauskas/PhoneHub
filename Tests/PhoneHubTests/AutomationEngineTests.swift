import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class AutomationEngineTests: XCTestCase {

    // The CLI rotates session_id on every `--resume`. `reply(_:)` must refuse to
    // spawn a resume without a captured (non-empty) id — otherwise it would
    // attach to the wrong or no conversation. This exercises that pure guard
    // without spawning a process.
    func testCanResumeRequiresNonEmptySessionId() {
        XCTAssertTrue(AutomationEngine.canResume(sessionId: "rotated-789"))
        XCTAssertFalse(AutomationEngine.canResume(sessionId: nil))
        XCTAssertFalse(AutomationEngine.canResume(sessionId: ""))
        XCTAssertFalse(AutomationEngine.canResume(sessionId: "   "))
    }

    func testLostSessionMessageIsUserFacing() {
        XCTAssertTrue(AutomationEngine.lostSessionMessage.contains("Lost session"))
        XCTAssertTrue(AutomationEngine.lostSessionMessage.lowercased().contains("start the goal again"))
    }

    func testAPIRunUsesRuntimeEventsAndFinishesWithoutCLI() async throws {
        let provider = AppSequenceProvider([
            LLMResponse(text: "Goal complete.", toolCalls: [])
        ])
        let client = AppRecordingMCPClient()
        let engine = AutomationEngine(
            backendAvailability: { _ in .available(path: "api") },
            apiRuntimeFactory: { _, _ in ApiAgentRuntime(provider: provider, client: client) }
        )
        engine.commandGate = { _ in nil }
        let preset = Preset(name: "API run", goal: "Open Settings", platforms: [.ios])
        let device = Device(id: "ios", platform: .ios, model: "iPhone",
                            osVersion: "18", status: "connected")

        engine.run(preset: preset, on: device, backend: .openai)
        try await waitUntil { engine.state == .finished }

        XCTAssertEqual(engine.log, ["Running “API run” on iPhone…", "Goal complete.", "Done."])
        XCTAssertTrue(client.started)
        XCTAssertTrue(client.stopped)
    }

    func testDisabledCapturePolicyIsResolvedForRunAndLoggedOnce() async throws {
        let provider = AppSequenceProvider([
            LLMResponse(text: "Done.", toolCalls: [])
        ])
        var receivedPlan: AutomationPlan?
        let engine = AutomationEngine(
            backendAvailability: { _ in .available(path: "api") },
            apiRuntimeFactory: { _, plan in
                receivedPlan = plan
                return ApiAgentRuntime(provider: provider, client: AppRecordingMCPClient())
            },
            screenCapturePolicyProvider: { .disabled }
        )
        engine.commandGate = { _ in nil }
        let preset = Preset(name: "Private run", goal: "Open Settings", platforms: [.ios])
        let device = Device(id: "ios", platform: .ios, model: "iPhone",
                            osVersion: "18", status: "connected")

        engine.run(preset: preset, on: device, backend: .openai)
        try await waitUntil { engine.state == .finished }

        XCTAssertEqual(receivedPlan?.screenCaptureDecision.allowsCapture, false)
        XCTAssertEqual(engine.log.filter {
            $0 == "screen capture disabled in settings — using text description only"
        }.count, 1)
    }

    func testBuilderActionUsesConstrainedOriginCapturesToolAndClearsOnDismiss() async throws {
        let provider = AppSequenceProvider([
            LLMResponse(
                text: nil,
                toolCalls: [LLMToolCall(id: "one", name: "press_home", argumentsJSON: "{}")]
            ),
            LLMResponse(text: "Done.", toolCalls: []),
        ])
        let engine = AutomationEngine(
            backendAvailability: { _ in .available(path: "api") },
            apiRuntimeFactory: { _, plan in
                XCTAssertTrue(plan.systemPreamble.contains("EXACTLY ONE"))
                return ApiAgentRuntime(provider: provider, client: AppRecordingMCPClient())
            }
        )
        engine.commandGate = { _ in nil }
        let device = Device(id: "ios", platform: .ios, model: "iPhone",
                            osVersion: "18", status: "connected")

        engine.runBuilderAction(goal: "go home", on: device, backend: .openai)
        XCTAssertTrue(engine.isBuilderAction)
        try await waitUntil { engine.state == .finished }

        XCTAssertEqual(engine.lastCapture, [CapturedCall(tool: "press_home", rawInput: "{}")])
        engine.dismissResult()
        XCTAssertFalse(engine.isBuilderAction)
        XCTAssertEqual(engine.state, .idle)
    }

    func testTerminalPresetRunAppendsHistoryRecord() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineHistory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let history = RunHistoryStore(directory: dir)
        let provider = AppSequenceProvider([
            LLMResponse(text: "Done here.", toolCalls: [])
        ])
        let engine = AutomationEngine(
            backendAvailability: { _ in .available(path: "api") },
            apiRuntimeFactory: { _, _ in
                ApiAgentRuntime(provider: provider, client: AppRecordingMCPClient())
            }
        )
        engine.commandGate = { _ in nil }
        engine.runHistoryStore = history
        let preset = Preset(name: "Hist preset", goal: "Tap Home", platforms: [.ios])
        let device = Device(id: "hist-ios", platform: .ios, model: "iPhone 15",
                            osVersion: "18", status: "connected")

        engine.run(preset: preset, on: device, backend: .openai)
        try await waitUntil { engine.state == .finished }

        let records = history.records(deviceId: "hist-ios")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].name, "Hist preset")
        XCTAssertEqual(records[0].kind, .preset)
        XCTAssertEqual(records[0].outcome, .finished)
        XCTAssertEqual(records[0].deviceName, "iPhone 15")
        XCTAssertFalse(records[0].log.isEmpty)
    }

    func testCondenseUsesTextOnlyAPICompletion() async throws {
        let engine = AutomationEngine(
            backendAvailability: { _ in .available(path: "keychain") },
            apiRuntimeFactory: { _, _ in throw LLMProviderFactoryError.unsupportedBackend },
            apiTextCompletion: { backend, prompt in
                XCTAssertEqual(backend, .openrouter)
                XCTAssertTrue(prompt.contains("Output ONLY the JSON array"))
                return "[]"
            }
        )
        engine.commandGate = { _ in nil }

        let result = try await engine.condense(goal: "Open Settings", rawSteps: [],
                                               backend: .openrouter)

        XCTAssertEqual(result, [])
        XCTAssertFalse(engine.isCondensing)
    }

    func testDescribeRecordingReusesTextOnlyAPICompletion() async throws {
        let engine = AutomationEngine(
            backendAvailability: { _ in .available(path: "keychain") },
            apiRuntimeFactory: { _, _ in throw LLMProviderFactoryError.unsupportedBackend },
            apiTextCompletion: { backend, prompt in
                XCTAssertEqual(backend, .openai)
                XCTAssertTrue(prompt.contains("4-12 words"))
                return "Open Settings and enable notifications"
            }
        )
        engine.commandGate = { _ in nil }

        let description = try await engine.describeRecording(
            rawSteps: [.tap(id: UUID(), label: nil, x: 10, y: 20)],
            backend: .openai
        )

        XCTAssertEqual(description, "Open Settings and enable notifications")
        XCTAssertFalse(engine.isCondensing)
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !predicate() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(predicate())
    }
}

actor AppSequenceProvider: LLMProvider {
    private var responses: [LLMResponse]
    init(_ responses: [LLMResponse]) { self.responses = responses }
    func send(messages: [LLMMessage], tools: [LLMToolDefinition]) async throws -> LLMResponse {
        guard !responses.isEmpty else { throw LLMProviderError.invalidResponse }
        return responses.removeFirst()
    }
}

final class AppRecordingMCPClient: McpToolClient, @unchecked Sendable {
    private(set) var started = false
    private(set) var stopped = false
    func start() async throws { started = true }
    func callTool(_ name: String, arguments: [String: Any],
                  timeoutSeconds: Double) async throws -> McpToolResult {
        McpToolResult(text: "ok", isError: false)
    }
    func stop() { stopped = true }
}
