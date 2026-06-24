import Foundation
import Observation
import PhoneHubCore

enum AutomationState: Equatable {
    case idle
    case running
    case stopped
    case finished
    case failed(String)
}

/// Drives a single AI preset run. Spawns a headless `claude` wired to the
/// phone-control MCP for the focused device's platform, streams its
/// stream-json output into a live log, and exposes a Stop control.
///
/// The exact `claude` command (verified against `claude --help`):
///   claude -p "<goal+device context>" \
///     --append-system-prompt "<neutral operational preamble>" \
///     --output-format stream-json --verbose \
///     --mcp-config <temp json file> \
///     --allowedTools "mcp__mirroir" | "mcp__androir" \
///     --max-turns <maxSteps> \
///     --permission-mode default
/// (no --dangerously-skip-permissions on this spawn; tools are restricted to the
///  phone MCP only.)
@Observable
@MainActor
final class AutomationEngine {
    private(set) var state: AutomationState = .idle
    private(set) var log: [String] = []
    private(set) var currentAction: String?
    private(set) var runningPreset: Preset?

    private var process: StreamingProcess?
    private var configURL: URL?

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Start a preset on a device. No-op if a run is already active.
    func run(preset: Preset, on device: Device) {
        guard !isRunning else { return }

        let plan: AutomationPlan
        do {
            plan = try buildAutomationPlan(preset: preset, device: device)
        } catch AutomationPlanError.platformMismatch {
            fail("This preset does not support \(device.platform == .ios ? "iOS" : "Android").")
            return
        } catch {
            fail("Could not prepare the run: \(error)")
            return
        }

        guard let claudePath = resolveClaude() else {
            fail("`claude` CLI not found (expected on PATH or ~/.local/bin).")
            return
        }

        // Write the MCP config to a temp file.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-mcp-\(UUID().uuidString).json")
        do {
            try plan.mcpConfigJSON.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            fail("Could not write MCP config: \(error)")
            return
        }
        configURL = url

        // Reset live state.
        state = .running
        runningPreset = preset
        currentAction = "Starting…"
        log = ["Running “\(preset.name)” on \(device.model)…"]

        let args = plan.arguments(mcpConfigPath: url.path)
        let proc = StreamingProcess(executablePath: claudePath, arguments: args)
        process = proc

        do {
            try proc.start(
                onLine: { [weak self] line in
                    Task { @MainActor in self?.handle(line: line) }
                },
                onExit: { [weak self] code, reason in
                    Task { @MainActor in self?.handleExit(code: code, reason: reason) }
                }
            )
        } catch {
            fail("Failed to launch claude: \(error)")
            cleanupConfig()
        }
    }

    /// Clear a finished/stopped/failed run from the UI and return to the list.
    func dismissResult() {
        guard !isRunning else { return }
        state = .idle
        runningPreset = nil
        currentAction = nil
        log = []
    }

    /// Stop the active run (terminate the process group).
    func stop() {
        process?.stop()
        if isRunning {
            state = .stopped
            currentAction = "Stopped"
            log.append("— Stopped by user —")
        }
    }

    // MARK: - Stream handling

    private func handle(line: String) {
        let event = StreamJSONParser.parseLine(line)
        guard let update = StreamJSONParser.update(for: event) else { return }
        if let logLine = update.logLine { log.append(logLine) }
        if let action = update.currentAction { currentAction = action }
        if update.finished {
            // Final state is settled on process exit; record intent here.
            if update.failed { currentAction = "Failed" }
        }
        // Keep the log bounded so a long run doesn't grow unbounded.
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    private func handleExit(code: Int32, reason: String) {
        cleanupConfig()
        process = nil
        switch state {
        case .stopped:
            break // user already stopped
        case .running:
            if code == 0 {
                state = .finished
                currentAction = "Finished"
            } else {
                // `reason` carries the last stderr lines so a launch failure
                // (e.g. "MCP server failed to start") is diagnosable.
                let msg = reason.isEmpty ? "claude exited with code \(code)" : "claude \(reason)"
                state = .failed(msg)
                currentAction = "Failed"
                log.append(msg)
            }
        default:
            break
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        currentAction = "Failed"
        log.append(message)
    }

    private func cleanupConfig() {
        if let url = configURL { try? FileManager.default.removeItem(at: url) }
        configURL = nil
    }

    /// Resolve the `claude` binary: Homebrew/system paths, then ~/.local/bin.
    private func resolveClaude() -> String? {
        if let path = resolveTool("claude") { return path }
        let local = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path
        return FileManager.default.isExecutableFile(atPath: local) ? local : nil
    }
}
