import XCTest
@testable import PhoneHubCore

final class LLMProviderTests: XCTestCase {
    private let tools = [
        LLMToolDefinition(
            name: "tap",
            description: "Tap the screen",
            parametersJSON: #"{"type":"object","properties":{"x":{"type":"number"}},"required":["x"]}"#
        )
    ]

    func testOpenAIRequestUsesFunctionToolsAndToolHistory() throws {
        let call = LLMToolCall(id: "call_1", name: "tap", argumentsJSON: #"{"x":42}"#)
        let messages = [
            LLMMessage(role: .system, content: "control phone"),
            LLMMessage(role: .user, content: "tap it"),
            LLMMessage(role: .assistant, content: nil, toolCalls: [call]),
            LLMMessage(role: .tool, content: "ok", toolCallID: "call_1")
        ]

        let data = try OpenAIWire.buildRequest(model: "gpt-test", messages: messages, tools: tools)
        let root = try json(data)
        XCTAssertEqual(root["model"] as? String, "gpt-test")
        let wireTools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        XCTAssertEqual(wireTools.first?["type"] as? String, "function")
        let function = try XCTUnwrap(wireTools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "tap")
        let wireMessages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        XCTAssertEqual(wireMessages[2]["role"] as? String, "assistant")
        XCTAssertEqual((wireMessages[2]["tool_calls"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(wireMessages[3]["tool_call_id"] as? String, "call_1")
    }

    func testOpenAIParsesTextResponse() throws {
        let response = Data(#"{"choices":[{"message":{"role":"assistant","content":"Done."}}]}"#.utf8)
        XCTAssertEqual(
            try OpenAIWire.parseResponse(response),
            LLMResponse(text: "Done.", toolCalls: [])
        )
    }

    func testOpenAIParsesMultipleToolCalls() throws {
        let response = Data(#"{"choices":[{"message":{"content":null,"tool_calls":[{"id":"a","type":"function","function":{"name":"tap","arguments":"{\"x\":1}"}},{"id":"b","type":"function","function":{"name":"press_home","arguments":"{}"}}]}}]}"#.utf8)
        let parsed = try OpenAIWire.parseResponse(response)
        XCTAssertEqual(parsed.toolCalls.map(\.id), ["a", "b"])
        XCTAssertEqual(parsed.toolCalls.map(\.name), ["tap", "press_home"])
        XCTAssertNil(parsed.text)
    }

    func testOpenAIAndOpenRouterRequestsUseCorrectEndpointsAndHeaders() throws {
        let openAI = try OpenAICompatibleProvider.request(
            endpoint: .openAI,
            apiKey: "fixture-credential",
            model: "gpt-test",
            messages: [],
            tools: []
        )
        XCTAssertEqual(openAI.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(openAI.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-credential")
        XCTAssertNil(openAI.value(forHTTPHeaderField: "HTTP-Referer"))

        let router = try OpenAICompatibleProvider.request(
            endpoint: .openRouter,
            apiKey: "fixture-credential",
            model: "router-test",
            messages: [],
            tools: []
        )
        XCTAssertEqual(router.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(router.value(forHTTPHeaderField: "HTTP-Referer"), "https://phonehub.local")
        XCTAssertEqual(router.value(forHTTPHeaderField: "X-Title"), "PhoneHub")
    }

    func testTextOnlyRequestsOmitEmptyTools() throws {
        let message = LLMMessage(role: .user, content: "Return JSON")
        let openAI = try json(OpenAIWire.buildRequest(
            model: "gpt-test", messages: [message], tools: []
        ))
        let anthropic = try json(AnthropicWire.buildRequest(
            model: "claude-test", messages: [message], tools: []
        ))

        XCTAssertNil(openAI["tools"])
        XCTAssertNil(anthropic["tools"])
    }

    func testAnthropicRequestUsesSystemAndNativeToolBlocks() throws {
        let call = LLMToolCall(id: "toolu_1", name: "tap", argumentsJSON: #"{"x":42}"#)
        let messages = [
            LLMMessage(role: .system, content: "control phone"),
            LLMMessage(role: .user, content: "tap it"),
            LLMMessage(role: .assistant, content: "Using tap", toolCalls: [call]),
            LLMMessage(role: .tool, content: "ok", toolCallID: "toolu_1", isError: false)
        ]

        let root = try json(AnthropicWire.buildRequest(
            model: "claude-test", messages: messages, tools: tools
        ))
        XCTAssertEqual(root["system"] as? String, "control phone")
        XCTAssertEqual(root["max_tokens"] as? Int, 4096)
        let wireTools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        XCTAssertNotNil(wireTools[0]["input_schema"] as? [String: Any])
        let wireMessages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let assistantContent = try XCTUnwrap(wireMessages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantContent.last?["type"] as? String, "tool_use")
        let resultContent = try XCTUnwrap(wireMessages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(resultContent[0]["tool_use_id"] as? String, "toolu_1")
    }

    func testAnthropicParsesTextAndToolCalls() throws {
        let response = Data(#"{"id":"msg_1","content":[{"type":"text","text":"Working"},{"type":"tool_use","id":"toolu_1","name":"tap","input":{"x":42}}],"stop_reason":"tool_use"}"#.utf8)
        let parsed = try AnthropicWire.parseResponse(response)
        XCTAssertEqual(parsed.text, "Working")
        XCTAssertEqual(parsed.toolCalls, [
            LLMToolCall(id: "toolu_1", name: "tap", argumentsJSON: #"{"x":42}"#)
        ])
    }

    func testAnthropicRequestUsesRequiredHeadersWithoutBodyInErrors() throws {
        let request = try AnthropicProvider.request(
            apiKey: "fixture-credential", model: "claude-test", messages: [], tools: []
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fixture-credential")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(LLMProviderError.httpStatus(401).localizedDescription,
                       "LLM provider request failed (HTTP 401).")
    }

    func testMalformedResponsesAreRejected() {
        XCTAssertThrowsError(try OpenAIWire.parseResponse(Data(#"{"choices":[]}"#.utf8)))
        XCTAssertThrowsError(try AnthropicWire.parseResponse(Data(#"{"content":"bad"}"#.utf8)))
    }

    func testOpenAIRequestEncodesImageAsDataURLContentPart() throws {
        let image = LLMImageContent(mediaType: "image/png", base64: Self.tinyPNGBase64)
        let message = LLMMessage(role: .user, content: "What is on screen?", image: image)
        let root = try json(OpenAIWire.buildRequest(model: "gpt-test", messages: [message], tools: []))
        let wireMessages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(wireMessages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[0]["text"] as? String, "What is on screen?")
        XCTAssertEqual(parts[1]["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(parts[1]["image_url"] as? [String: Any])
        XCTAssertEqual(
            imageURL["url"] as? String,
            "data:image/png;base64,\(Self.tinyPNGBase64)"
        )
    }

    func testAnthropicRequestEncodesImageAsBase64SourceBlock() throws {
        let image = LLMImageContent(mediaType: "image/png", base64: Self.tinyPNGBase64)
        let message = LLMMessage(role: .user, content: "What is on screen?", image: image)
        let root = try json(AnthropicWire.buildRequest(
            model: "claude-test", messages: [message], tools: []
        ))
        let wireMessages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let blocks = try XCTUnwrap(wireMessages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
        XCTAssertEqual(blocks[0]["text"] as? String, "What is on screen?")
        XCTAssertEqual(blocks[1]["type"] as? String, "image")
        let source = try XCTUnwrap(blocks[1]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, Self.tinyPNGBase64)
    }

    func testTextOnlyUserContentUnchangedWithoutImage() throws {
        let message = LLMMessage(role: .user, content: "plain")
        let openAI = try json(OpenAIWire.buildRequest(
            model: "gpt-test", messages: [message], tools: []
        ))
        let anthropic = try json(AnthropicWire.buildRequest(
            model: "claude-test", messages: [message], tools: []
        ))
        let openAIMessages = try XCTUnwrap(openAI["messages"] as? [[String: Any]])
        let anthropicMessages = try XCTUnwrap(anthropic["messages"] as? [[String: Any]])
        XCTAssertEqual(openAIMessages[0]["content"] as? String, "plain")
        XCTAssertEqual(anthropicMessages[0]["content"] as? String, "plain")
    }

    /// 1×1 PNG — fixture only; never log production screenshot bytes.
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
