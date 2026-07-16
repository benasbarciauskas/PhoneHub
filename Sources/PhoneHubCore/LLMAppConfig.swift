import Foundation

public struct LLMAppConfig: Codable, Equatable, Sendable {
    public static let defaultModels = [
        "openrouter": "anthropic/claude-3.5-sonnet",
        "openai": "gpt-4.1",
        "anthropic": "claude-sonnet-4-20250514"
    ]

    public static let `default` = LLMAppConfig(
        selectedBackend: .claude,
        models: defaultModels
    )

    public var selectedBackend: AgentBackend
    public private(set) var models: [String: String]

    public init(selectedBackend: AgentBackend, models: [String: String]) {
        self.selectedBackend = selectedBackend
        self.models = models
    }

    public func model(forProvider provider: String) -> String {
        let value = models[provider]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? Self.defaultModels[provider] ?? "" : value
    }

    public mutating func setModel(_ model: String, forProvider provider: String) {
        models[provider] = model
    }
}

public struct LLMConfigStore {
    public static let storageKey = "llmAppConfig"
    public static let legacyBackendKey = "agentBackend"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LLMAppConfig {
        if let data = defaults.data(forKey: Self.storageKey),
           let config = try? JSONDecoder().decode(LLMAppConfig.self, from: data) {
            return config
        }
        var config = LLMAppConfig.default
        if let rawValue = defaults.string(forKey: Self.legacyBackendKey),
           let backend = AgentBackend(rawValue: rawValue) {
            config.selectedBackend = backend
        }
        return config
    }

    public func save(_ config: LLMAppConfig) throws {
        defaults.set(try JSONEncoder().encode(config), forKey: Self.storageKey)
    }
}
