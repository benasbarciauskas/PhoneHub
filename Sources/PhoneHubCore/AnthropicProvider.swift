import Foundation

public enum AnthropicWire {
    public static func buildRequest(model: String,
                                    messages: [LLMMessage],
                                    tools: [LLMToolDefinition]) throws -> Data {
        let system = messages
            .filter { $0.role == .system }
            .compactMap(\.content)
            .joined(separator: "\n\n")
        let wireMessages = try messages.compactMap { message -> [String: Any]? in
            switch message.role {
            case .system:
                return nil
            case .tool:
                return [
                    "role": "user",
                    "content": [[
                        "type": "tool_result",
                        "tool_use_id": message.toolCallID ?? "",
                        "content": message.content ?? "",
                        "is_error": message.isError
                    ]]
                ]
            case .user:
                return ["role": "user", "content": message.content ?? ""]
            case .assistant:
                guard !message.toolCalls.isEmpty else {
                    return ["role": "assistant", "content": message.content ?? ""]
                }
                var blocks: [[String: Any]] = []
                if let content = message.content, !content.isEmpty {
                    blocks.append(["type": "text", "text": content])
                }
                for call in message.toolCalls {
                    blocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": try LLMWireJSON.object(from: call.argumentsJSON)
                    ])
                }
                return ["role": "assistant", "content": blocks]
            }
        }
        let wireTools = try tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": try LLMWireJSON.object(from: tool.parametersJSON)
            ] as [String: Any]
        }
        var root: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": wireMessages
        ]
        if !system.isEmpty { root["system"] = system }
        if !wireTools.isEmpty { root["tools"] = wireTools }
        return try LLMWireJSON.data(root)
    }

    public static func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else {
            throw LLMProviderError.invalidResponse
        }
        let textParts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        let calls = try content.compactMap { block -> LLMToolCall? in
            guard block["type"] as? String == "tool_use" else { return nil }
            guard let id = block["id"] as? String,
                  let name = block["name"] as? String,
                  let input = block["input"] else {
                throw LLMProviderError.invalidResponse
            }
            return LLMToolCall(id: id, name: name,
                               argumentsJSON: try LLMWireJSON.compactString(input))
        }
        let text = textParts.joined(separator: "\n")
        guard !text.isEmpty || !calls.isEmpty else { throw LLMProviderError.invalidResponse }
        return LLMResponse(text: text.isEmpty ? nil : text, toolCalls: calls)
    }
}

public struct AnthropicProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func send(messages: [LLMMessage],
                     tools: [LLMToolDefinition]) async throws -> LLMResponse {
        let request = try Self.request(apiKey: apiKey, model: model,
                                       messages: messages, tools: tools)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMProviderError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LLMProviderError.httpStatus(http.statusCode)
            }
            return try AnthropicWire.parseResponse(data)
        } catch let error as LLMProviderError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LLMProviderError.transport
        }
    }

    public static func request(apiKey: String, model: String,
                               messages: [LLMMessage], tools: [LLMToolDefinition]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try AnthropicWire.buildRequest(model: model, messages: messages, tools: tools)
        return request
    }
}
