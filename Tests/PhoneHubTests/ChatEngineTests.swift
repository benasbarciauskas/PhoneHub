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
}
