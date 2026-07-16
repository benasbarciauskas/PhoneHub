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

public struct ApiAgentRunResult: Equatable, Sendable {
    public let outcome: ApiAgentOutcome
    public let messages: [LLMMessage]

    public init(outcome: ApiAgentOutcome, messages: [LLMMessage]) {
        self.outcome = outcome
        self.messages = messages
    }
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
    private let sensitiveValues: [String]

    public init(provider: any LLMProvider, client: any McpToolClient,
                sensitiveValues: [String] = []) {
        self.provider = provider
        self.client = client
        self.sensitiveValues = sensitiveValues.filter { !$0.isEmpty }
    }

    public static func live(provider: any LLMProvider,
                            plan: AutomationPlan,
                            sensitiveValues: [String] = []) throws -> ApiAgentRuntime {
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
            client: McpDirectClient(command: executable, arguments: arguments),
            sensitiveValues: sensitiveValues
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
                    onEvent: @escaping @Sendable (StreamEvent) async -> Void) async -> ApiAgentRunResult {
        var messages = [LLMMessage(role: .system, content: systemPreamble)] + priorMessages
        if !prompt.isEmpty { messages.append(LLMMessage(role: .user, content: prompt)) }
        do {
            try await client.start()
        } catch {
            return ApiAgentRunResult(
                outcome: await fail(redact(error.localizedDescription), onEvent: onEvent),
                messages: transcript(messages)
            )
        }
        defer { client.stop() }

        let tools = phoneControlTools(serverName: serverName)
        var toolCallCount = 0

        do {
            while true {
                try Task.checkCancellation()
                let response: LLMResponse
                do {
                    response = try await provider.send(messages: messages, tools: tools)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as LLMProviderError {
                    return ApiAgentRunResult(
                        outcome: await fail(redact(error.localizedDescription), onEvent: onEvent),
                        messages: transcript(messages)
                    )
                } catch {
                    return ApiAgentRunResult(
                        outcome: await fail("The LLM provider request failed.", onEvent: onEvent),
                        messages: transcript(messages)
                    )
                }

                switch Self.decision(for: response) {
                case .needInput(let question):
                    messages.append(LLMMessage(role: .assistant, content: response.text))
                    await onEvent(.needInput(question: question))
                    return ApiAgentRunResult(outcome: .needsInput(question),
                                             messages: transcript(messages))
                case .complete(let text):
                    if let text, !text.isEmpty {
                        messages.append(LLMMessage(role: .assistant, content: text))
                        await onEvent(.assistantText(text))
                    }
                    await onEvent(.result(subtype: "success", text: nil, sessionId: nil))
                    return ApiAgentRunResult(outcome: .completed(text),
                                             messages: transcript(messages))
                case .callTools:
                    if let text = response.text, !text.isEmpty { await onEvent(.assistantText(text)) }
                    messages.append(LLMMessage(role: .assistant, content: response.text,
                                               toolCalls: response.toolCalls))
                    for call in response.toolCalls {
                        guard toolCallCount < maxToolCalls else {
                            await onEvent(.result(subtype: "error", text: "Step limit reached.",
                                                  sessionId: nil))
                            return ApiAgentRunResult(outcome: .maxStepsReached,
                                                     messages: transcript(messages))
                        }
                        let arguments = try Self.decodeArguments(call.argumentsJSON)
                        let rawInput = StreamJSONParser.jsonString(input: arguments)
                        await onEvent(.toolUse(
                            name: call.name,
                            summary: StreamJSONParser.summarize(input: arguments),
                            rawInput: rawInput
                        ))
                        toolCallCount += 1
                        let result = try await client.callTool(
                            call.name, arguments: arguments, timeoutSeconds: 30
                        )
                        await onEvent(.toolResult(result.text))
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
            return ApiAgentRunResult(outcome: .cancelled, messages: transcript(messages))
        } catch {
            return ApiAgentRunResult(
                outcome: await fail(redact(error.localizedDescription), onEvent: onEvent),
                messages: transcript(messages)
            )
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
                      onEvent: @Sendable (StreamEvent) async -> Void) async -> ApiAgentOutcome {
        await onEvent(.result(subtype: "error", text: message, sessionId: nil))
        return .failed(message)
    }

    private func transcript(_ messages: [LLMMessage]) -> [LLMMessage] {
        messages.filter { $0.role != .system }
    }

    private func redact(_ message: String) -> String {
        sensitiveValues.reduce(message) { text, secret in
            text.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
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
