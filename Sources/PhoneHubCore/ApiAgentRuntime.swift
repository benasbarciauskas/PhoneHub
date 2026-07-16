import Foundation

public protocol McpToolClient: Sendable {
    func start() async throws
    func callTool(_ name: String, arguments: [String: Any],
                  timeoutSeconds: Double) async throws -> McpToolResult
    func stop()
}

extension McpDirectClient: McpToolClient {}

public enum ApiAgentDecision: Equatable, Sendable {
    case needInput(String)
    case callTools
    case complete(String?)
}

public enum ApiAgentOutcome: Equatable, Sendable {
    case completed(String?)
    case needsInput(String)
    case failed(String)
    case maxStepsReached
    case cancelled
}

public enum ApiAgentRuntimeError: Error, LocalizedError, Equatable {
    case invalidMCPConfiguration
    case invalidToolArguments

    public var errorDescription: String? {
        switch self {
        case .invalidMCPConfiguration:
            return "Could not prepare the phone tool connection."
        case .invalidToolArguments:
            return "The model returned invalid tool arguments."
        }
    }
}

public struct McpLaunchConfiguration: Equatable, Sendable {
    public let command: String
    public let arguments: [String]

    public init(command: String, arguments: [String]) {
        self.command = command
        self.arguments = arguments
    }
}

public final class ApiAgentRuntime: @unchecked Sendable {
    private let provider: any LLMProvider
    private let client: any McpToolClient

    public init(provider: any LLMProvider, client: any McpToolClient) {
        self.provider = provider
        self.client = client
    }

    public static func live(provider: any LLMProvider,
                            plan: AutomationPlan) throws -> ApiAgentRuntime {
        let configuration = try mcpLaunchConfiguration(plan: plan)
        let executable: String
        let arguments: [String]
        if configuration.command.contains("/") {
            executable = configuration.command
            arguments = configuration.arguments
        } else if let resolved = resolveTool(configuration.command) {
            executable = resolved
            arguments = configuration.arguments
        } else {
            executable = "/usr/bin/env"
            arguments = [configuration.command] + configuration.arguments
        }
        return ApiAgentRuntime(
            provider: provider,
            client: McpDirectClient(command: executable, arguments: arguments)
        )
    }

    public static func decision(for response: LLMResponse) -> ApiAgentDecision {
        if let text = response.text,
           let question = StreamJSONParser.detectNeedInput(text) {
            return .needInput(question)
        }
        if !response.toolCalls.isEmpty { return .callTools }
        return .complete(response.text)
    }

    public func run(systemPreamble: String,
                    prompt: String,
                    priorMessages: [LLMMessage],
                    maxToolCalls: Int,
                    serverName: String,
                    onEvent: @escaping @Sendable (StreamEvent) -> Void) async -> ApiAgentOutcome {
        do {
            try await client.start()
        } catch {
            return fail(error.localizedDescription, onEvent: onEvent)
        }
        defer { client.stop() }

        var messages = [LLMMessage(role: .system, content: systemPreamble)] + priorMessages
        if !prompt.isEmpty { messages.append(LLMMessage(role: .user, content: prompt)) }
        let tools = phoneControlTools(serverName: serverName)
        var toolCallCount = 0

        do {
            while true {
                try Task.checkCancellation()
                let response = try await provider.send(messages: messages, tools: tools)

                switch Self.decision(for: response) {
                case .needInput(let question):
                    onEvent(.needInput(question: question))
                    return .needsInput(question)
                case .complete(let text):
                    if let text, !text.isEmpty { onEvent(.assistantText(text)) }
                    onEvent(.result(subtype: "success", text: nil, sessionId: nil))
                    return .completed(text)
                case .callTools:
                    if let text = response.text, !text.isEmpty { onEvent(.assistantText(text)) }
                    messages.append(LLMMessage(role: .assistant, content: response.text,
                                               toolCalls: response.toolCalls))
                    for call in response.toolCalls {
                        guard toolCallCount < maxToolCalls else {
                            onEvent(.result(subtype: "error", text: "Step limit reached.",
                                            sessionId: nil))
                            return .maxStepsReached
                        }
                        let arguments = try Self.decodeArguments(call.argumentsJSON)
                        let rawInput = StreamJSONParser.jsonString(input: arguments)
                        onEvent(.toolUse(
                            name: call.name,
                            summary: StreamJSONParser.summarize(input: arguments),
                            rawInput: rawInput
                        ))
                        toolCallCount += 1
                        let result = try await client.callTool(
                            call.name, arguments: arguments, timeoutSeconds: 30
                        )
                        onEvent(.toolResult(result.text))
                        messages.append(LLMMessage(
                            role: .tool,
                            content: result.text,
                            toolCallID: call.id,
                            isError: result.isError
                        ))
                    }
                }
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return fail(error.localizedDescription, onEvent: onEvent)
        }
    }

    static func decodeArguments(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let arguments = object as? [String: Any] else {
            throw ApiAgentRuntimeError.invalidToolArguments
        }
        return arguments
    }

    private func fail(_ message: String,
                      onEvent: @Sendable (StreamEvent) -> Void) -> ApiAgentOutcome {
        onEvent(.result(subtype: "error", text: message, sessionId: nil))
        return .failed(message)
    }

    public static func mcpLaunchConfiguration(plan: AutomationPlan) throws
        -> McpLaunchConfiguration {
        guard let data = plan.mcpConfigJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let server = servers[plan.serverName] as? [String: Any],
              let command = server["command"] as? String,
              let arguments = server["args"] as? [String] else {
            throw ApiAgentRuntimeError.invalidMCPConfiguration
        }
        return McpLaunchConfiguration(command: command, arguments: arguments)
    }
}
