import Foundation

public enum CondenseError: Error, LocalizedError {
    case encoding(String)
    case invalidResponse(String)
    case backend(String)

    public var errorDescription: String? {
        switch self {
        case .encoding(let message): return "Could not encode raw steps: \(message)"
        case .invalidResponse(let message): return "Invalid condensed automation: \(message)"
        case .backend(let message): return message
        }
    }
}

public enum CondensePrompt {
    public static func prompt(goal: String, rawSteps: [AutomationStep]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do { data = try encoder.encode(rawSteps) }
        catch { throw CondenseError.encoding(error.localizedDescription) }
        let json = String(decoding: data, as: UTF8.self)
        return """
        Condense a raw phone automation trace into the minimal correct action sequence for the goal. \
        Remove mistakes, dead ends, repeated probes, and backtracking. Preserve required waits. \
        Output ONLY the JSON array. No markdown, code fences, explanation, or surrounding object.

        Every item must have a fresh UUID string in "id" and one discriminator in "type". \
        Allowed types: launchApp|tap|doubleTap|longPress|typeText|pressKey|swipe|pressHome|pressBack|pressAppSwitcher|scrollTo|openURL|wait|aiStep. \
        Fields: launchApp{name}; tap/doubleTap{label?,x?,y?}; longPress{label?,x?,y?,durationMs}; \
        typeText{text}; pressKey{key}; swipe{direction}; pressHome/pressBack/pressAppSwitcher{}; \
        scrollTo{text,direction}; openURL{url}; wait{ms}; aiStep{prompt}. \
        For point actions include a semantic label when known; otherwise include both x and y.

        Goal:
        \(goal)

        Raw steps:
        \(json)
        """
    }

    public static func arguments(prompt: String, backend: AgentBackend) -> [String] {
        switch backend {
        case .claude:
            return ["-p", prompt, "--output-format", "text"]
        case .codex:
            return ["exec", "--skip-git-repo-check", "-s", "read-only", prompt]
        case .openrouter, .openai, .anthropic:
            // Condensing is CLI-only; callers must not launch these empty arguments.
            return []
        }
    }

    public static func parseResponse(_ response: String) throws -> [AutomationStep] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "[", trimmed.last == "]", let data = trimmed.data(using: .utf8) else {
            throw CondenseError.invalidResponse("expected a JSON array only")
        }
        let steps: [AutomationStep]
        do { steps = try JSONDecoder().decode([AutomationStep].self, from: data) }
        catch { throw CondenseError.invalidResponse(error.localizedDescription) }
        for step in steps { try validate(step) }
        return steps
    }

    private static func validate(_ step: AutomationStep) throws {
        let directions = ["up", "down", "left", "right"]
        switch step {
        case let .launchApp(_, name): try require(name, field: "name")
        case let .tap(_, label, x, y), let .doubleTap(_, label, x, y):
            try requirePoint(label: label, x: x, y: y)
        case let .longPress(_, label, x, y, durationMs):
            try requirePoint(label: label, x: x, y: y)
            guard durationMs > 0 else { throw CondenseError.invalidResponse("durationMs must be positive") }
        case let .typeText(_, text): try require(text, field: "text")
        case let .pressKey(_, key): try require(key, field: "key")
        case let .swipe(_, direction):
            guard directions.contains(direction) else { throw CondenseError.invalidResponse("invalid swipe direction") }
        case .pressHome, .pressBack, .pressAppSwitcher: break
        case let .scrollTo(_, text, direction):
            try require(text, field: "text")
            guard directions.contains(direction) else { throw CondenseError.invalidResponse("invalid scroll direction") }
        case let .openURL(_, url): try require(url, field: "url")
        case let .wait(_, ms):
            guard ms >= 0 else { throw CondenseError.invalidResponse("wait must not be negative") }
        case let .aiStep(_, prompt): try require(prompt, field: "prompt")
        }
    }

    private static func require(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CondenseError.invalidResponse("\(field) must not be empty")
        }
    }

    private static func requirePoint(label: String?, x: Double?, y: Double?) throws {
        let hasLabel = !(label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard hasLabel || (x != nil && y != nil) else {
            throw CondenseError.invalidResponse("point action needs a label or x and y")
        }
        guard (x == nil) == (y == nil) else {
            throw CondenseError.invalidResponse("x and y must be provided together")
        }
    }
}
