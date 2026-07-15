import Foundation

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case tool
        case system
    }

    public let id: UUID
    public let role: Role
    public let text: String
    public let timestamp: Date

    public init(role: Role, text: String, timestamp: Date = .now) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public struct DeviceChat: Codable, Equatable, Sendable {
    public var messages: [ChatMessage]
    public var sessionId: String?
    public var backend: AgentBackend

    public init(messages: [ChatMessage], sessionId: String?, backend: AgentBackend) {
        self.messages = messages
        self.sessionId = sessionId
        self.backend = backend
    }

    public static let empty = DeviceChat(messages: [], sessionId: nil, backend: .claude)
}

public final class ChatStore: @unchecked Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func load(deviceId: String) -> DeviceChat {
        let url = fileURL(for: deviceId)
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DeviceChat.self, from: data)
        } catch {
            print("PhoneHub: Could not load persisted chat; using an empty transcript.")
            return .empty
        }
    }

    public func save(_ chat: DeviceChat, deviceId: String) {
        var persisted = chat
        if persisted.messages.count > 200 {
            persisted.messages = Array(persisted.messages.suffix(200))
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(persisted)
            try data.write(to: fileURL(for: deviceId), options: .atomic)
        } catch {
            print("PhoneHub: Could not save persisted chat.")
        }
    }

    private func fileURL(for deviceId: String) -> URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let sanitized = deviceId.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return directory.appendingPathComponent("\(sanitized).json", isDirectory: false)
    }
}
