import Foundation

public enum AutomationPlanError: Error, Equatable {
    case platformMismatch
    case invalidSerial
}

public enum AgentBackend: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case openrouter
    case openai
    case anthropic

    public var isCLI: Bool {
        switch self {
        case .claude, .codex: return true
        case .openrouter, .openai, .anthropic: return false
        }
    }

    public var isAPI: Bool { !isCLI }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .openrouter: return "OpenRouter"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }
}

/// Everything needed to launch a headless agent for one preset run.
/// Pure data so it can be built and unit-tested without spawning anything.
public struct AutomationPlan: Equatable {
    public let backend: AgentBackend
    public var prompt: String           // the goal + device context (user prompt)
    public let systemPreamble: String   // appended system prompt
    public let mcpConfigJSON: String    // contents of the --mcp-config file
    public let allowedTools: String     // value for --allowedTools
    public let maxTurns: Int            // value for --max-turns
    public let serverName: String       // "mirroir" | "androir"

    /// Full argv passed to the resolved backend binary (excludes the binary path).
    /// mcpConfigPath is the temp file the caller has written mcpConfigJSON into.
    public func arguments(mcpConfigPath: String) -> [String] {
        switch backend {
        case .claude:
            return [
            "-p", prompt,
            "--append-system-prompt", systemPreamble,
            "--output-format", "stream-json",
            "--verbose",
            "--mcp-config", mcpConfigPath,
            "--allowedTools", allowedTools,
            "--max-turns", String(maxTurns),
            "--permission-mode", "default"
            ]
        case .codex:
            // Codex has no append-system-prompt, allowedTools, or max-turns
            // equivalents. The preamble carries the step cap and configuring only
            // this MCP server limits phone-tool exposure. Keep its shell sandbox
            // read-only: the MCP server is the intended side-effect surface.
            return [
                "exec",
                "--json",
                "--skip-git-repo-check",
                "-s", "read-only"
            ] + codexMCPArguments + ["\(systemPreamble)\n\n\(prompt)"]
        case .openrouter, .openai, .anthropic:
            // API backends run in ApiAgentRuntime and must never spawn a CLI.
            return []
        }
    }

    /// Full argv to RESUME an existing session with the user's reply. Reuses the
    /// SAME mcp-config / allowedTools / max-turns / preamble as the initial run so
    /// the resumed turn keeps the phone-control tools and step cap. Verified flag:
    /// `claude --resume <id> -p "<reply>" ...` (from `claude --help`: `-r, --resume`).
    public func resumeArguments(sessionId: String,
                                reply: String,
                                mcpConfigPath: String) -> [String] {
        switch backend {
        case .claude:
            return [
            "--resume", sessionId,
            "-p", reply,
            "--append-system-prompt", systemPreamble,
            "--output-format", "stream-json",
            "--verbose",
            "--mcp-config", mcpConfigPath,
            "--allowedTools", allowedTools,
            "--max-turns", String(maxTurns),
            "--permission-mode", "default"
            ]
        case .codex:
            // `exec resume` inherits the original session's read-only sandbox.
            return ["exec", "resume", sessionId, "--json"]
                + codexMCPArguments
                + [reply]
        case .openrouter, .openai, .anthropic:
            // API chat keeps normalized message history instead of CLI sessions.
            return []
        }
    }

    private var codexMCPArguments: [String] {
        let args: String
        switch serverName {
        case "mirroir":
            args = "[\"-y\",\"mirroir-mcp\",\"--dangerously-skip-permissions\"]"
        case "androir":
            args = "[\"-y\",\"androir-mcp\"]"
        default:
            args = "[]"
        }
        return [
            "-c", "mcp_servers.\(serverName).command=npx",
            "-c", "mcp_servers.\(serverName).args=\(args)",
            "-c", "mcp_servers.\(serverName).default_tools_approval_mode=\"approve\""
        ]
    }
}

/// Operational system preamble for the spawned agent.
public let automationSystemPreamble = """
You control a phone through the attached tools. Achieve the goal. Use only the \
attached phone-control tools. Stop when the goal is met or the step cap is \
reached. Dwell briefly on content as a human would.

If you hit a blocker you cannot resolve yourself (a login wall, 2FA, captcha, an \
ambiguous choice, or missing information), do NOT guess. Emit a single line \
exactly `NEED_INPUT: <your concise question>` and end your turn. You will be \
resumed with the user's answer.
"""

public let chatSystemPreamble = """
You are operating a phone through the attached tools, in an interactive chat \
with the user. Answer conversationally. When the user asks about the screen, \
look at it with the tools and describe what you see. When asked to act, act \
with the tools. Use only the attached phone-control tools. If unsure, ask the \
user instead of guessing — just end your reply with the question.
"""

private struct PlatformWiring {
    let server: String
    let mcpJSON: String
    let allowedTools: String
    let deviceContext: String
}

private func platformWiring(for device: Device) throws -> PlatformWiring {
    switch device.platform {
    case .ios:
        return PlatformWiring(
            server: "mirroir",
            mcpJSON: mcpConfig(
                server: "mirroir",
                command: "npx",
                args: ["-y", "mirroir-mcp", "--dangerously-skip-permissions"]
            ),
            allowedTools: "mcp__mirroir__*",
            deviceContext: "Platform: iOS."
        )
    case .android:
        guard isValidSerial(device.id) else {
            throw AutomationPlanError.invalidSerial
        }
        return PlatformWiring(
            server: "androir",
            mcpJSON: mcpConfig(
                server: "androir",
                command: "npx",
                args: ["-y", "androir-mcp"]
            ),
            allowedTools: "mcp__androir__*",
            deviceContext: "Platform: Android. Device serial: \(device.id). "
                + "Pass this serial as the `serial` argument to every androir tool call."
        )
    }
}

/// Build the launch plan for a preset on a device. Pure function — no I/O.
public func buildAutomationPlan(
    preset: Preset,
    device: Device,
    backend: AgentBackend = .claude
) throws -> AutomationPlan {
    guard preset.supports(device.platform) else {
        throw AutomationPlanError.platformMismatch
    }

    let wiring = try platformWiring(for: device)

    var goal = preset.goal
    if let app = preset.app, !app.isEmpty {
        goal = "First make sure the \(app) app is open. \(goal)"
    }

    let prompt = "\(goal)\n\n\(wiring.deviceContext)\n"
        + "You have a hard cap of \(preset.maxSteps) tool calls; stop before exceeding it."

    return AutomationPlan(
        backend: preset.backend ?? backend,
        prompt: prompt,
        systemPreamble: automationSystemPreamble,
        mcpConfigJSON: wiring.mcpJSON,
        allowedTools: wiring.allowedTools,
        maxTurns: preset.maxSteps,
        serverName: wiring.server
    )
}

/// Render the exact system-preamble + user-prompt payload for a preset run.
/// Preview errors are converted to readable notes so the detail editor remains useful.
public func presetPayloadPreview(preset: Preset, device: Device) -> String {
    do {
        let plan = try buildAutomationPlan(preset: preset, device: device)
        return "\(plan.systemPreamble)\n\n\(plan.prompt)"
    } catch AutomationPlanError.platformMismatch {
        let platformName = device.platform == .ios ? "iOS" : "Android"
        return "Preview unavailable: this preset does not support \(platformName)."
    } catch AutomationPlanError.invalidSerial {
        return "Preview unavailable: the Android device serial is invalid."
    } catch {
        return "Preview unavailable: \(error.localizedDescription)"
    }
}

public func buildChatPlan(
    device: Device,
    backend: AgentBackend = .claude
) throws -> AutomationPlan {
    let wiring = try platformWiring(for: device)
    return AutomationPlan(
        backend: backend,
        prompt: "",
        systemPreamble: "\(chatSystemPreamble)\n\n\(wiring.deviceContext)",
        mcpConfigJSON: wiring.mcpJSON,
        allowedTools: wiring.allowedTools,
        maxTurns: 25,
        serverName: wiring.server
    )
}

/// Build a minimal `--mcp-config` JSON for one stdio MCP server.
public func mcpConfig(server: String, command: String, args: [String]) -> String {
    let argsJSON = args.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", ")
    return """
    {"mcpServers": {"\(server)": {"command": "\(jsonEscape(command))", "args": [\(argsJSON)]}}}
    """
}

private func jsonEscape(_ s: String) -> String {
    var out = ""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        default: out.unicodeScalars.append(ch)
        }
    }
    return out
}
