import Foundation

public struct LLMAppConfig: Codable, Equatable, Sendable {
    public static let defaultModels = [
        "openrouter": "anthropic/claude-3.5-sonnet",
        "openai": "gpt-4.1",
        "anthropic": "claude-sonnet-4-20250514"
    ]

    public static let `default` = LLMAppConfig(
        selectedBackend: .claude,
        models: defaultModels,
        vision: false,
        screenDescriberMode: .auto,
        preferKnownSteps: false,
        screenCapturePolicy: .duringRunsOnly
    )

    public var selectedBackend: AgentBackend
    public private(set) var models: [String: String]
    /// When true, API backends attach phone screenshots each decision step.
    /// Ignored for claude/codex CLIs (they handle vision via MCP themselves).
    public var vision: Bool
    /// mirroir-mcp screen describer mode (iOS only). Default Auto matches today.
    public var screenDescriberMode: ScreenDescriberMode
    /// App default for reusing compiled/recorded skills (preset may override).
    public var preferKnownSteps: Bool
    /// Controls whether phone-control MCP clients may capture images or video.
    public var screenCapturePolicy: ScreenCapturePolicy

    public init(selectedBackend: AgentBackend, models: [String: String],
                vision: Bool = false,
                screenDescriberMode: ScreenDescriberMode = .auto,
                preferKnownSteps: Bool = false,
                screenCapturePolicy: ScreenCapturePolicy = .duringRunsOnly) {
        self.selectedBackend = selectedBackend
        self.models = models
        self.vision = vision
        self.screenDescriberMode = screenDescriberMode
        self.preferKnownSteps = preferKnownSteps
        self.screenCapturePolicy = screenCapturePolicy
    }

    public func model(forProvider provider: String) -> String {
        let value = models[provider]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? Self.defaultModels[provider] ?? "" : value
    }

    public mutating func setModel(_ model: String, forProvider provider: String) {
        models[provider] = model
    }

    enum CodingKeys: String, CodingKey {
        case selectedBackend, models, vision, screenDescriberMode, preferKnownSteps,
             screenCapturePolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedBackend = try container.decode(AgentBackend.self, forKey: .selectedBackend)
        models = try container.decode([String: String].self, forKey: .models)
        vision = try container.decodeIfPresent(Bool.self, forKey: .vision) ?? false
        screenDescriberMode = try container.decodeIfPresent(
            ScreenDescriberMode.self, forKey: .screenDescriberMode
        ) ?? .auto
        preferKnownSteps = try container.decodeIfPresent(Bool.self, forKey: .preferKnownSteps) ?? false
        screenCapturePolicy = try container.decodeIfPresent(
            ScreenCapturePolicy.self, forKey: .screenCapturePolicy
        ) ?? .duringRunsOnly
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
