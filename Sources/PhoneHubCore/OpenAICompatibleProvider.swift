import Foundation

public enum OpenAIWire {
    public static func buildRequest(model: String,
                                    messages: [LLMMessage],
                                    tools: [LLMToolDefinition]) throws -> Data {
        let wireMessages = messages.map { message -> [String: Any] in
            var object: [String: Any] = ["role": message.role.rawValue]
            if message.role == .tool {
                object["content"] = message.content ?? ""
                object["tool_call_id"] = message.toolCallID ?? ""
                return object
            }
            object["content"] = message.content ?? NSNull()
            if !message.toolCalls.isEmpty {
                object["tool_calls"] = message.toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.argumentsJSON]
                    ] as [String: Any]
                }
            }
            return object
        }
        let wireTools = try tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": try LLMWireJSON.object(from: tool.parametersJSON)
                ]
            ] as [String: Any]
        }
        return try LLMWireJSON.data([
            "model": model,
            "messages": wireMessages,
            "tools": wireTools
        ])
    }

    public static func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw LLMProviderError.invalidResponse
        }
        let text = (message["content"] as? String)?.nonEmpty
        let calls = try (message["tool_calls"] as? [[String: Any]] ?? []).map { object in
            guard let id = object["id"] as? String,
                  let function = object["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let arguments = function["arguments"] as? String else {
                throw LLMProviderError.invalidResponse
            }
            return LLMToolCall(id: id, name: name, argumentsJSON: arguments)
        }
        guard text != nil || !calls.isEmpty else { throw LLMProviderError.invalidResponse }
        return LLMResponse(text: text, toolCalls: calls)
    }
}

public struct OpenAICompatibleProvider: LLMProvider {
    public enum Endpoint: Sendable {
        case openAI
        case openRouter

        var url: URL {
            switch self {
            case .openAI: return URL(string: "https://api.openai.com/v1/chat/completions")!
            case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            }
        }
    }

    private let endpoint: Endpoint
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(endpoint: Endpoint, apiKey: String, model: String,
                session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func send(messages: [LLMMessage],
                     tools: [LLMToolDefinition]) async throws -> LLMResponse {
        let request = try Self.request(endpoint: endpoint, apiKey: apiKey,
                                       model: model, messages: messages, tools: tools)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMProviderError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LLMProviderError.httpStatus(http.statusCode)
            }
            return try OpenAIWire.parseResponse(data)
        } catch let error as LLMProviderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LLMProviderError.transport
        }
    }

    public static func request(endpoint: Endpoint, apiKey: String, model: String,
                               messages: [LLMMessage], tools: [LLMToolDefinition]) throws -> URLRequest {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if endpoint == .openRouter {
            request.setValue("https://phonehub.local", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("PhoneHub", forHTTPHeaderField: "X-Title")
        }
        request.httpBody = try OpenAIWire.buildRequest(model: model, messages: messages, tools: tools)
        return request
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
