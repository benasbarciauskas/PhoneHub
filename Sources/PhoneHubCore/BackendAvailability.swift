import Foundation

public enum BackendStatus: Equatable, Sendable {
    case available(path: String)
    case missing(hint: String)
}

public enum BackendAvailability {
    public static func check(
        _ backend: AgentBackend,
        resolver: (String) -> String? = defaultResolver,
        keyLookup: (String) -> String? = defaultKeyLookup
    ) -> BackendStatus {
        if backend.isAPI {
            let key = keyLookup(backend.rawValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return key.isEmpty
                ? .missing(hint: "Add your \(backend.displayName) API key in Settings.")
                : .available(path: "api")
        }
        let binary = backend.rawValue
        if let path = resolver(binary) {
            return .available(path: path)
        }
        switch backend {
        case .claude:
            return .missing(hint: "Install the Claude CLI (https://claude.com/claude-code) and run `claude` once to log in. PhoneHub uses your own login — it stores no keys.")
        case .codex:
            return .missing(hint: "Install the Codex CLI (npm i -g @openai/codex) and run `codex` once to log in. PhoneHub uses your own login — it stores no keys.")
        case .openrouter, .openai, .anthropic:
            preconditionFailure("API backends are handled before CLI resolution")
        }
    }

    public static func defaultKeyLookup(_ provider: String) -> String? {
        try? KeychainStore().key(provider: provider)
    }

    public static func defaultResolver(_ binary: String) -> String? {
        if let path = resolveTool(binary) { return path }
        let local = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/\(binary)").path
        return FileManager.default.isExecutableFile(atPath: local) ? local : nil
    }
}
