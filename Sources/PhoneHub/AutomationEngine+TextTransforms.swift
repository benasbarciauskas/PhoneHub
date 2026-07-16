import Foundation
import PhoneHubCore

extension AutomationEngine {
    /// Rewrite rough text into a clear phone-automation goal. Text-only spawn —
    /// no tools or MCP configuration.
    func refine(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard case let .available(path: claudePath) = BackendAvailability.check(.claude) else {
            throw RefineError.claudeNotFound
        }
        isRefining = true
        defer { isRefining = false }

        let args = RefinePrompt.arguments(for: trimmed)
        let result: CommandResult = try await Task.detached(priority: .userInitiated) {
            try runToolAt(path: claudePath, args: args, timeout: 60)
        }.value

        guard result.exitCode == 0 else {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RefineError.failed(err.isEmpty ? "claude exited with code \(result.exitCode)" : err)
        }
        let output = (String(data: result.stdout, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw RefineError.emptyOutput }
        return output
    }

    func condense(goal: String, rawSteps: [AutomationStep],
                  backend: AgentBackend) async throws -> [AutomationStep] {
        let prompt = try CondensePrompt.prompt(goal: goal, rawSteps: rawSteps)
        let output = try await completeTextTransform(prompt: prompt, backend: backend)
        return try CondensePrompt.parseResponse(output)
    }

    func describeRecording(rawSteps: [AutomationStep],
                           backend: AgentBackend) async throws -> String {
        let prompt = try CondensePrompt.descriptionPrompt(rawSteps: rawSteps)
        let output = try await completeTextTransform(prompt: prompt, backend: backend)
        return try CondensePrompt.parseDescription(output)
    }

    private func completeTextTransform(prompt: String,
                                       backend: AgentBackend) async throws -> String {
        guard !isBusy else { throw CondenseError.backend("A device run is active.") }
        guard !isCondensing else { throw CondenseError.backend("An AI timeline action is active.") }
        let availability = backendAvailability(backend)
        guard case let .available(path) = availability else {
            if case let .missing(hint) = availability { throw CondenseError.backend(hint) }
            throw CondenseError.backend("\(backend.rawValue) is unavailable.")
        }
        isCondensing = true
        defer { isCondensing = false }

        if backend.isAPI {
            return try await apiTextCompletion(backend, prompt)
        }

        let arguments = CondensePrompt.arguments(prompt: prompt, backend: backend)
        let result: CommandResult = try await Task.detached(priority: .userInitiated) {
            try runToolAt(path: path, args: arguments, timeout: 120)
        }.value
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CondenseError.backend(stderr.isEmpty
                ? "\(backend.rawValue) exited with code \(result.exitCode)" : stderr)
        }
        return String(decoding: result.stdout, as: UTF8.self)
    }
}
