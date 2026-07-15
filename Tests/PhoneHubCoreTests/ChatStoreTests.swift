import XCTest
@testable import PhoneHubCore

final class ChatStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testRoundTripSaveLoad() throws {
        let directory = try temporaryDirectory()
        let store = ChatStore(directory: directory)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let chat = DeviceChat(
            messages: [ChatMessage(role: .user, text: "Hello", timestamp: timestamp)],
            sessionId: "session-1",
            backend: .claude
        )

        store.save(chat, deviceId: "device-1")

        XCTAssertEqual(store.load(deviceId: "device-1"), chat)
    }

    func testCorruptFileReturnsEmpty() throws {
        let directory = try temporaryDirectory()
        try Data("not json".utf8).write(to: directory.appendingPathComponent("device.json"))

        XCTAssertEqual(ChatStore(directory: directory).load(deviceId: "device"), .empty)
    }

    func testUnsafeDeviceIDStaysInsideStoreDirectory() throws {
        let directory = try temporaryDirectory()
        let store = ChatStore(directory: directory)
        store.save(.empty, deviceId: "../evil/../../x")

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        let root = directory.standardizedFileURL.path + "/"
        XCTAssertTrue(files[0].standardizedFileURL.path.hasPrefix(root))
        XCTAssertEqual(files[0].lastPathComponent, ".._evil_.._.._x.json")
    }

    func testSaveCapsPersistedMessagesAtTwoHundred() throws {
        let directory = try temporaryDirectory()
        let store = ChatStore(directory: directory)
        let messages = (0..<250).map { ChatMessage(role: .user, text: "\($0)") }

        store.save(DeviceChat(messages: messages, sessionId: nil, backend: .claude),
                   deviceId: "device")

        let loaded = store.load(deviceId: "device")
        XCTAssertEqual(loaded.messages.count, 200)
        XCTAssertEqual(loaded.messages.first?.text, "50")
        XCTAssertEqual(loaded.messages.last?.text, "249")
    }
}
