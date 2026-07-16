import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class ChatEngineTests: XCTestCase {
    private let device = Device(
        id: "test-device",
        platform: .ios,
        model: "iPhone",
        osVersion: "18.0",
        status: "device"
    )

    func testSendRejectsWhilePresetRunIsBusy() {
        let engine = makeEngine()

        let accepted = engine.send("Keep this text", on: device, presetEngineBusy: true)

        XCTAssertFalse(accepted)
        XCTAssertEqual(engine.chat.messages.last?.role, .system)
    }

    func testSendRejectsWhenBackendIsMissing() {
        let engine = makeEngine(backendStatus: .missing(hint: "Install backend"))

        let accepted = engine.send("Keep this too", on: device, presetEngineBusy: false)

        XCTAssertFalse(accepted)
        XCTAssertEqual(engine.chat.messages.last?.text, "Install backend")
    }

    func testSendAcceptsCodexAndAppendsUserMessage() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ChatStore(directory: directory)
        store.save(
            DeviceChat(messages: [], sessionId: nil, backend: .codex),
            deviceId: device.id
        )
        let engine = ChatEngine(
            store: store,
            backendAvailability: { _ in .available(path: "/usr/bin/false") }
        )

        let accepted = engine.send(
            "Use codex",
            on: device,
            backend: .codex,
            presetEngineBusy: false
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(engine.chat.messages.first?.role, .user)
        XCTAssertEqual(engine.chat.messages.first?.text, "Use codex")
    }

    func testSendWithAPIBackendStoresFinalAssistantText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = AppSequenceProvider([
            LLMResponse(text: "The screen shows Settings.", toolCalls: [])
        ])
        let client = AppRecordingMCPClient()
        let engine = ChatEngine(
            store: ChatStore(directory: directory),
            backendAvailability: { _ in .available(path: "api") },
            apiRuntimeFactory: { _, _ in ApiAgentRuntime(provider: provider, client: client) }
        )

        XCTAssertTrue(engine.send("What is visible?", on: device,
                                  backend: .anthropic, presetEngineBusy: false))
        try await waitUntil { !engine.isBusy }

        XCTAssertEqual(engine.chat.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(engine.chat.messages.last?.text, "The screen shows Settings.")
        XCTAssertTrue(client.started)
        XCTAssertTrue(client.stopped)
    }

    func testDisabledCapturePolicyIsResolvedForTurnAndLoggedOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = AppSequenceProvider([
            LLMResponse(text: "Text-only answer.", toolCalls: [])
        ])
        var receivedPlan: AutomationPlan?
        let engine = ChatEngine(
            store: ChatStore(directory: directory),
            backendAvailability: { _ in .available(path: "api") },
            apiRuntimeFactory: { _, plan in
                receivedPlan = plan
                return ApiAgentRuntime(provider: provider, client: AppRecordingMCPClient())
            },
            screenCapturePolicyProvider: { .disabled }
        )

        XCTAssertTrue(engine.send(
            "What is visible?", on: device, backend: .openai, presetEngineBusy: false
        ))
        try await waitUntil { !engine.isBusy }

        XCTAssertEqual(receivedPlan?.screenCaptureDecision.allowsCapture, false)
        XCTAssertEqual(engine.chat.messages.filter {
            $0.text == "screen capture disabled in settings — using text description only"
        }.count, 1)
    }

    private func makeEngine(
        backendStatus: BackendStatus = .available(path: "/usr/bin/false")
    ) -> ChatEngine {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return ChatEngine(
            store: ChatStore(directory: directory),
            backendAvailability: { _ in backendStatus }
        )
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !predicate() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(predicate())
    }
}
