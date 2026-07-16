import Foundation

public enum LLMProviderFactoryError: Error, LocalizedError, Equatable {
    case unsupportedBackend
    case missingKey

    public var errorDescription: String? {
        switch self {
        case .unsupportedBackend: return "This backend does not use an API provider."
        case .missingKey: return "The API key is not configured."
        }
    }
}

public enum LLMProviderFactory {
    public static func make(backend: AgentBackend, apiKey: String,
                            model: String) throws -> any LLMProvider {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderFactoryError.missingKey
        }
        switch backend {
        case .openrouter:
            return OpenAICompatibleProvider(endpoint: .openRouter, apiKey: apiKey, model: model)
        case .openai:
            return OpenAICompatibleProvider(endpoint: .openAI, apiKey: apiKey, model: model)
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey, model: model)
        case .claude, .codex:
            throw LLMProviderFactoryError.unsupportedBackend
        }
    }
}

public func makeConfiguredAPIRuntime(backend: AgentBackend,
                                     plan: AutomationPlan) throws -> ApiAgentRuntime {
    let keyStore = KeychainStore()
    guard let key = try keyStore.key(provider: backend.rawValue) else {
        throw LLMProviderFactoryError.missingKey
    }
    let config = LLMConfigStore().load()
    let provider = try LLMProviderFactory.make(
        backend: backend,
        apiKey: key,
        model: config.model(forProvider: backend.rawValue)
    )
    return try ApiAgentRuntime.live(provider: provider, plan: plan, sensitiveValues: [key])
}

public func configuredAPITextCompletion(backend: AgentBackend,
                                        prompt: String) async throws -> String {
    guard let key = try KeychainStore().key(provider: backend.rawValue) else {
        throw LLMProviderFactoryError.missingKey
    }
    let config = LLMConfigStore().load()
    let provider = try LLMProviderFactory.make(
        backend: backend,
        apiKey: key,
        model: config.model(forProvider: backend.rawValue)
    )
    let response = try await provider.send(
        messages: [LLMMessage(role: .user, content: prompt)],
        tools: []
    )
    guard let text = response.text else { throw LLMProviderError.invalidResponse }
    return text
}
