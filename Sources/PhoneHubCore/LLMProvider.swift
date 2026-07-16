import Foundation

public enum LLMRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct LLMToolCall: Equatable, Sendable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct LLMMessage: Equatable, Sendable {
    public let role: LLMRole
    public let content: String?
    public let toolCallID: String?
    public let toolCalls: [LLMToolCall]
    public let isError: Bool

    public init(role: LLMRole,
                content: String?,
                toolCallID: String? = nil,
                toolCalls: [LLMToolCall] = [],
                isError: Bool = false) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.isError = isError
    }
}

public struct LLMToolDefinition: Equatable, Sendable {
    public let name: String
    public let description: String
    public let parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public struct LLMResponse: Equatable, Sendable {
    public let text: String?
    public let toolCalls: [LLMToolCall]

    public init(text: String?, toolCalls: [LLMToolCall]) {
        self.text = text
        self.toolCalls = toolCalls
    }
}

public protocol LLMProvider: Sendable {
    func send(messages: [LLMMessage], tools: [LLMToolDefinition]) async throws -> LLMResponse
}

public enum LLMProviderError: Error, LocalizedError, Equatable {
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case transport

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Could not create the LLM provider request."
        case .invalidResponse: return "The LLM provider returned an invalid response."
        case .httpStatus(let status): return "LLM provider request failed (HTTP \(status))."
        case .transport: return "Could not connect to the LLM provider."
        }
    }
}

enum LLMWireJSON {
    static func object(from json: String) throws -> Any {
        guard let data = json.data(using: .utf8) else { throw LLMProviderError.invalidRequest }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func data(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw LLMProviderError.invalidRequest
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func compactString(_ object: Any) throws -> String {
        String(decoding: try data(object), as: UTF8.self)
    }
}
