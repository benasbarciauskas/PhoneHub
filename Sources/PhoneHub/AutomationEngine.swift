import Foundation
import Observation
import PhoneHubCore

enum AutomationState: Equatable {
    case idle
    case running
    case awaitingInput(question: String)
    case stopped
    case finished
    case failed(String)
}

enum RefineError: Error, LocalizedError {
    case claudeNotFound
    case emptyOutput
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound: return "`claude` CLI not found."
        case .emptyOutput: return "Refine returned nothing."
        case .failed(let m): return m
        }
    }
}

/// Drives a single AI preset run. Spawns a headless `claude` wired to the
/// phone-control MCP for the focused device's platform, streams its
/// stream-json output into a live log, and exposes a Stop control.
///
/// Interactive blockers: if the agent emits `NEED_INPUT: <question>` and then
/// ends its turn, the run pauses in `.awaitingInput`; `reply(_:)` resumes the
/// SAME claude session with the user's answer, reusing the stored plan's flags.
///
/// The exact `claude` command (verified against `claude --help`):
///   claude -p "<goal+device context>" \
///     --append-system-prompt "<neutral operational preamble>" \
///     --output-format stream-json --verbose \
///     --mcp-config <temp json file> \
///     --allowedTools "mcp__mirroir__*" | "mcp__androir__*" \
///     --max-turns <maxSteps> \
///     --permission-mode default
/// Resume (verified flag `-r, --resume`):
///   claude --resume <sessionId> -p "<reply>" <same flags as above>
/// (no --dangerously-skip-permissions on this spawn; tools are restricted to the
///  phone MCP only.)
@Observable
@MainActor
final class AutomationEngine {
    private(set) var state: AutomationState = .idle
    private(set) var log: [String] = []
    private(set) var currentAction: String?
    private(set) var runningPreset: Preset?
    private(set) var isRefining = false

    private var process: StreamingProcess?
    private var configURL: URL?

    // Interactive-resume state: kept across the awaitingInput pause.
    private var currentPlan: AutomationPlan?
    private var sessionId: String?
    private var pendingQuestion: String?

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isAwaitingInput: Bool {
        if case .awaitingInput = state { return true }
        return false
    }

    /// Whether a new run can be launched (single active run guard). True only at
    /// rest — a paused (awaitingInput) run still owns the session.
    var isBusy: Bool {
        switch state {
        case .running, .awaitingInput: return true
        default: return false
        }
    }

    /// Start a saved preset on a device. No-op if a run is already active/paused.
    func run(preset: Preset, on device: Device) {
        guard !isBusy else { return }
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
        launch(plan: plan, preset: preset, device: device,
               header: "Running “\(preset.name)” on \(device.model)…")
    }

    /// Run typed text as a one-off goal on the focused device. The transient
    /// preset is never saved; it goes through the SAME plan/spawn path.
    func runAdhoc(goal: String, on device: Device) {
        guard !isBusy else { return }
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = Preset(name: "Command",
                            goal: trimmed,
                            platforms: [device.platform])
        let plan: AutomationPlan
        do {
            plan = try buildAutomationPlan(preset: preset, device: device)
        } catch {
            fail("Could not prepare the run: \(error)")
            return
        }
        launch(plan: plan, preset: preset, device: device,
               header: "Running command on \(device.model)…")
    }

    /// Spawn the initial `claude` for a prepared plan.
    private func launch(plan: AutomationPlan, preset: Preset, device: Device, header: String) {
        guard let claudePath = resolveClaude() else {
            fail("`claude` CLI not found (expected on PATH or ~/.local/bin).")
            return
        }
        guard let url = writeConfig(plan.mcpConfigJSON) else { return }
        configURL = url
        currentPlan = plan
        sessionId = nil
        pendingQuestion = nil

        state = .running
        runningPreset = preset
        currentAction = "Starting…"
        log = [header]

        spawn(executablePath: claudePath, args: plan.arguments(mcpConfigPath: url.path))
    }

    /// Resume the paused run with the user's answer (same session + flags).
    func reply(_ text: String) {
        guard case .awaitingInput = state,
              let plan = currentPlan,
              let session = sessionId,
              let url = configURL else { return }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        guard let claudePath = resolveClaude() else {
            fail("`claude` CLI not found (expected on PATH or ~/.local/bin).")
            return
        }
        pendingQuestion = nil
        state = .running
        currentAction = "Resuming…"
        log.append("You: \(answer)")

        let args = plan.resumeArguments(sessionId: session, reply: answer,
                                        mcpConfigPath: url.path)
        spawn(executablePath: claudePath, args: args)
    }

    private func spawn(executablePath: String, args: [String]) {
        let proc = StreamingProcess(executablePath: executablePath, arguments: args)
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

    /// Rewrite rough text into a clear phone-automation goal. Text-only spawn —
    /// NO tools, NO --mcp-config. Returns the rewritten goal. Throws on failure;
    /// callers leave the original text unchanged on error.
    func refine(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard let claudePath = resolveClaude() else { throw RefineError.claudeNotFound }
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
        let out = (String(data: result.stdout, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw RefineError.emptyOutput }
        return out
    }

    /// Clear a finished/stopped/failed run from the UI and return to the list.
    func dismissResult() {
        guard !isBusy else { return }
        state = .idle
        runningPreset = nil
        currentAction = nil
        currentPlan = nil
        sessionId = nil
        pendingQuestion = nil
        log = []
    }

    /// Stop the active or paused run (terminate the process group).
    func stop() {
        process?.stop()
        if isBusy {
            state = .stopped
            currentAction = "Stopped"
            pendingQuestion = nil
            log.append("— Stopped by user —")
        }
    }

    // MARK: - Stream handling

    private func handle(line: String) {
        let event = StreamJSONParser.parseLine(line)
        // Capture the session id from the init event so we can resume later.
        if case let .system(_, sid) = event, let sid, !sid.isEmpty {
            sessionId = sid
        }
        // Remember a pending question; the pause is settled on process exit.
        if case let .needInput(question) = event {
            pendingQuestion = question
        }
        guard let update = StreamJSONParser.update(for: event) else { return }
        if let logLine = update.logLine { log.append(logLine) }
        if let action = update.currentAction { currentAction = action }
        if update.finished, update.failed { currentAction = "Failed" }
        // Keep the log bounded so a long run doesn't grow unbounded.
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    private func handleExit(code: Int32, reason: String) {
        process = nil
        switch state {
        case .stopped:
            cleanupConfig()
        case .running:
            // A pending NEED_INPUT pauses the run instead of finishing/failing.
            if let question = pendingQuestion {
                pendingQuestion = nil
                state = .awaitingInput(question: question)
                currentAction = "Needs input"
                return // keep configURL + sessionId + plan for the resume
            }
            if code == 0 {
                state = .finished
                currentAction = "Finished"
            } else {
                let msg = reason.isEmpty ? "claude exited with code \(code)" : "claude \(reason)"
                state = .failed(msg)
                currentAction = "Failed"
                log.append(msg)
            }
            cleanupConfig()
        default:
            cleanupConfig()
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        currentAction = "Failed"
        log.append(message)
    }

    private func writeConfig(_ json: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-mcp-\(UUID().uuidString).json")
        do {
            try json.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            fail("Could not write MCP config: \(error)")
            return nil
        }
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
