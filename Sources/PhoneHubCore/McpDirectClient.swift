import Foundation

public struct McpToolResult: Equatable, Sendable {
    public let text: String
    public let isError: Bool
    /// Optional image payload from MCP `image` content blocks (never log this).
    public let imageBase64: String?
    public let imageMediaType: String?

    public init(text: String, isError: Bool,
                imageBase64: String? = nil, imageMediaType: String? = nil) {
        self.text = text
        self.isError = isError
        self.imageBase64 = imageBase64
        self.imageMediaType = imageMediaType
    }
}

public enum McpDirectClientError: Error, LocalizedError {
    case notStarted
    case invalidResponse
    case server(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .notStarted: return "MCP client is not running."
        case .invalidResponse: return "MCP server returned an invalid response."
        case .server(let message): return "MCP server error: \(message)"
        case .timedOut: return "MCP tool call timed out."
        }
    }
}

public final class McpDirectClient: @unchecked Sendable {
    private let command: String
    private let arguments: [String]
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let mailbox = ResponseMailbox()
    private let bufferLock = NSLock()
    private var outputBuffer = Data()

    public init(command: String, arguments: [String]) {
        self.command = command
        self.arguments = arguments
    }

    deinit { stop() }

    public func start() async throws {
        guard !process.isRunning else { return }
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        errorOutput.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        try process.run()

        let id = await mailbox.newID()
        try write(Self.encodeRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "phonehub", "version": "1.0"]
        ], id: id))
        _ = try await response(for: id, timeoutSeconds: 10)
        try write(Self.encodeNotification(method: "notifications/initialized", params: [:]))
    }

    public func callTool(_ name: String, arguments: [String: Any],
                         timeoutSeconds: Double) async throws -> McpToolResult {
        guard process.isRunning else { throw McpDirectClientError.notStarted }
        let id = await mailbox.newID()
        try write(Self.encodeRequest(method: "tools/call",
                                     params: ["name": name, "arguments": arguments], id: id))
        let response = try await response(for: id, timeoutSeconds: timeoutSeconds)
        return try Self.extractToolResult(json: response)
    }

    public func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        errorOutput.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    public static func encodeRequest(method: String, params: [String: Any], id: Int) throws -> Data {
        try encode(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }

    public static func decodeResponse(line: String, expectedID: Int) throws -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw McpDirectClientError.invalidResponse
        }
        guard (object["id"] as? NSNumber)?.intValue == expectedID else { return nil }
        return object
    }

    public static func extractToolResult(json: [String: Any]) throws -> McpToolResult {
        if let error = json["error"] as? [String: Any] {
            throw McpDirectClientError.server(error["message"] as? String ?? "Unknown error")
        }
        guard let result = json["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]] else {
            throw McpDirectClientError.invalidResponse
        }
        let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let image = content.compactMap(Self.imagePayload(from:)).first
        return McpToolResult(
            text: text,
            isError: result["isError"] as? Bool ?? false,
            imageBase64: image?.base64,
            imageMediaType: image?.mediaType
        )
    }

    /// MCP image block: `{type:"image", data, mimeType}` or nested `source`.
    private static func imagePayload(from block: [String: Any]) -> (base64: String, mediaType: String)? {
        guard (block["type"] as? String) == "image" else { return nil }
        if let data = block["data"] as? String, !data.isEmpty {
            let media = (block["mimeType"] as? String)
                ?? (block["media_type"] as? String)
                ?? "image/png"
            return (data, media)
        }
        if let source = block["source"] as? [String: Any],
           let data = source["data"] as? String, !data.isEmpty {
            let media = (source["media_type"] as? String)
                ?? (source["mimeType"] as? String)
                ?? "image/png"
            return (data, media)
        }
        return nil
    }

    private static func encodeNotification(method: String, params: [String: Any]) throws -> Data {
        try encode(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw McpDirectClientError.invalidResponse
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    private func write(_ data: Data) throws {
        guard process.isRunning else { throw McpDirectClientError.notStarted }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        bufferLock.lock()
        outputBuffer.append(data)
        var lines: [Data] = []
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            lines.append(outputBuffer.prefix(upTo: newline))
            outputBuffer.removeSubrange(...newline)
        }
        bufferLock.unlock()

        for data in lines {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue else { continue }
            Task { await mailbox.store(object, id: id) }
        }
    }

    private func response(for id: Int, timeoutSeconds: Double) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try Task.checkCancellation()
            if let response = await mailbox.take(id: id) {
                if let error = response["error"] as? [String: Any] {
                    throw McpDirectClientError.server(error["message"] as? String ?? "Unknown error")
                }
                return response
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw McpDirectClientError.timedOut
    }
}

private actor ResponseMailbox {
    private var nextID = 0
    private var responses: [Int: [String: Any]] = [:]

    func newID() -> Int { nextID += 1; return nextID }
    func store(_ response: [String: Any], id: Int) { responses[id] = response }
    func take(id: Int) -> [String: Any]? { responses.removeValue(forKey: id) }
}
