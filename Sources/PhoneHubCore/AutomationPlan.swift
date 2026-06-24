import Foundation

/// Default location of the androir-mcp entry point. Overridable for tests.
public let defaultAndroirEntry =
    "/Volumes/X10 Pro/Ruflo/projects/androir-mcp/dist/index.js"

public enum AutomationPlanError: Error, Equatable {
    case platformMismatch
    case invalidSerial
}

/// Everything needed to launch the headless `claude` agent for one preset run.
/// Pure data so it can be built and unit-tested without spawning anything.
public struct AutomationPlan: Equatable {
    public let prompt: String           // the goal + device context (user prompt)
    public let systemPreamble: String   // appended system prompt
    public let mcpConfigJSON: String    // contents of the --mcp-config file
    public let allowedTools: String     // value for --allowedTools
    public let maxTurns: Int            // value for --max-turns
    public let serverName: String       // "mirroir" | "androir"

    /// Full argv passed to the resolved `claude` binary (excludes the binary path).
    /// mcpConfigPath is the temp file the caller has written mcpConfigJSON into.
    public func arguments(mcpConfigPath: String) -> [String] {
        [
            "-p", prompt,
            "--append-system-prompt", systemPreamble,
            "--output-format", "stream-json",
            "--verbose",
            "--mcp-config", mcpConfigPath,
            "--allowedTools", allowedTools,
            "--max-turns", String(maxTurns),
            "--permission-mode", "default"
        ]
    }
}

/// Neutral, operational system preamble for the spawned agent. No
/// personal-use disclaimer and no evasion/anti-detection instructions.
public let automationSystemPreamble = """
You control a phone through the attached tools. Achieve the goal. Use only the \
attached phone-control tools. Stop when the goal is met or the step cap is \
reached. Dwell briefly on content as a human would.
"""

/// Build the launch plan for a preset on a device. Pure function — no I/O.
public func buildAutomationPlan(
    preset: Preset,
    device: Device,
    androirEntry: String = defaultAndroirEntry
) throws -> AutomationPlan {
    guard preset.supports(device.platform) else {
        throw AutomationPlanError.platformMismatch
    }

    let serverName: String
    let mcpConfigJSON: String
    let allowedTools: String
    var deviceContext: String

    switch device.platform {
    case .ios:
        serverName = "mirroir"
        allowedTools = "mcp__mirroir"
        mcpConfigJSON = mcpConfig(
            server: "mirroir",
            command: "npx",
            args: ["-y", "mirroir-mcp", "--dangerously-skip-permissions"]
        )
        deviceContext = "Platform: iOS."
    case .android:
        guard isValidSerial(device.id) else {
            throw AutomationPlanError.invalidSerial
        }
        serverName = "androir"
        allowedTools = "mcp__androir"
        mcpConfigJSON = mcpConfig(
            server: "androir",
            command: "node",
            args: [androirEntry]
        )
        // androir takes the serial as a per-tool `serial` argument; tell the
        // agent to pass it so multi-device setups target the right phone.
        deviceContext = "Platform: Android. Device serial: \(device.id). "
            + "Pass this serial as the `serial` argument to every androir tool call."
    }

    var goal = preset.goal
    if let app = preset.app, !app.isEmpty {
        goal = "First make sure the \(app) app is open. \(goal)"
    }

    let prompt = "\(goal)\n\n\(deviceContext)\n"
        + "You have a hard cap of \(preset.maxSteps) tool calls; stop before exceeding it."

    return AutomationPlan(
        prompt: prompt,
        systemPreamble: automationSystemPreamble,
        mcpConfigJSON: mcpConfigJSON,
        allowedTools: allowedTools,
        maxTurns: preset.maxSteps,
        serverName: serverName
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
