import Foundation

public enum BackendStatus: Equatable, Sendable {
    case available(path: String)
    case missing(hint: String)
}

public enum BackendAvailability {
    public static func check(
        _ backend: AgentBackend,
        resolver: (String) -> String? = defaultResolver
    ) -> BackendStatus {
        let binary = backend.rawValue
        if let path = resolver(binary) {
            return .available(path: path)
        }
        switch backend {
        case .claude:
            return .missing(hint: "Install the Claude CLI (https://claude.com/claude-code) and run `claude` once to log in. PhoneHub uses your own login — it stores no keys.")
        case .codex:
            return .missing(hint: "Install the Codex CLI (npm i -g @openai/codex) and run `codex` once to log in. PhoneHub uses your own login — it stores no keys.")
        }
    }

    public static func defaultResolver(_ binary: String) -> String? {
        if let path = resolveTool(binary) { return path }
        let local = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/\(binary)").path
        return FileManager.default.isExecutableFile(atPath: local) ? local : nil
    }
}
