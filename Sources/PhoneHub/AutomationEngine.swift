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

/// Drives a single AI preset run. Spawns the selected headless agent wired to the
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
/// Resume (verified `-r, --resume`): claude --resume <id> -p "<reply>" <same flags>.
/// No --dangerously-skip-permissions; tools restricted to the phone MCP only.
@Observable
@MainActor
final class AutomationEngine {
    private(set) var state: AutomationState = .idle
    private(set) var log: [String] = []
    private(set) var currentAction: String?
    private(set) var runningPreset: Preset?
    private(set) var isRefining = false
    private(set) var isCondensing = false
    private(set) var lastCapture: [CapturedCall] = []

    /// Optional; when set, every terminal preset run is appended to per-device history.
    var runHistoryStore: RunHistoryStore?

    private var process: StreamingProcess?
    private var configURL: URL?
    private var apiTask: Task<Void, Never>?
    private var apiMessages: [LLMMessage] = []
    private let backendAvailability: (AgentBackend) -> BackendStatus
    private let apiRuntimeFactory: (AgentBackend, AutomationPlan) throws -> ApiAgentRuntime
    private let apiTextCompletion: (AgentBackend, String) async throws -> String

    // Interactive-resume state: kept across the awaitingInput pause.
    private var currentPlan: AutomationPlan?
    private var sessionId: String?
    private var pendingQuestion: String?
    private var currentCapture: [CapturedCall] = []

    /// Active run metadata for history; cleared once a terminal outcome is recorded.
    var historyContext: RunHistoryContext?

    init(
        backendAvailability: @escaping (AgentBackend) -> BackendStatus = {
            BackendAvailability.check($0)
        },
        apiRuntimeFactory: @escaping (AgentBackend, AutomationPlan) throws -> ApiAgentRuntime = {
            try makeConfiguredAPIRuntime(backend: $0, plan: $1)
        },
        apiTextCompletion: @escaping (AgentBackend, String) async throws -> String = {
            try await configuredAPITextCompletion(backend: $0, prompt: $1)
        }
    ) {
        self.backendAvailability = backendAvailability
        self.apiRuntimeFactory = apiRuntimeFactory
        self.apiTextCompletion = apiTextCompletion
    }

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
    func run(preset: Preset, on device: Device, backend: AgentBackend = .claude,
             preferKnownSteps: Bool = false) {
        guard !isBusy else { return }
        beginHistory(name: preset.name, device: device)
        do {
            let plan = try buildAutomationPlan(
                preset: preset, device: device, backend: backend,
                preferKnownSteps: preferKnownSteps)
            launch(plan: plan, preset: preset, device: device,
                   header: "Running “\(preset.name)” on \(device.model)…")
        } catch AutomationPlanError.platformMismatch {
            fail("This preset does not support \(device.platform == .ios ? "iOS" : "Android").")
        } catch {
            fail("Could not prepare the run: \(error)")
        }
    }

    /// Run typed text as a one-off goal on the focused device. The transient
    /// preset is never saved; it goes through the SAME plan/spawn path.
    func runAdhoc(goal: String, on device: Device, backend: AgentBackend = .claude,
                  preferKnownSteps: Bool = false) {
        guard !isBusy else { return }
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = Preset(name: "Command", goal: trimmed, platforms: [device.platform])
        beginHistory(name: preset.name, device: device)
        do {
            let plan = try buildAutomationPlan(
                preset: preset, device: device, backend: backend,
                preferKnownSteps: preferKnownSteps)
            launch(plan: plan, preset: preset, device: device,
                   header: "Running command on \(device.model)…")
        } catch {
            fail("Could not prepare the run: \(error)")
        }
    }

    /// Spawn the selected backend for a prepared plan.
    private func launch(plan: AutomationPlan, preset: Preset, device: Device, header: String) {
        let backendStatus = backendAvailability(plan.backend)
        guard case let .available(path: executablePath) = backendStatus else {
            if case let .missing(hint) = backendStatus { fail(hint) }
            return
        }
        // Ensure history is bound even if a caller invoked launch without beginHistory.
        if historyContext == nil {
            beginHistory(name: preset.name, device: device)
        }
        currentPlan = plan
        sessionId = nil
        pendingQuestion = nil
        currentCapture = []
        lastCapture = []
        apiMessages = []

        state = .running
        runningPreset = preset
        currentAction = "Starting…"
        log = [header]

        // iOS: write mirroir screenDescriberMode into ~/.mirroir-mcp/config.json before spawn.
        prepareMirroirConfigForSpawn(serverName: plan.serverName)

        if plan.backend.isAPI {
            startAPI(plan: plan, prompt: plan.prompt, priorMessages: [])
            return
        }
        guard let url = writeConfig(plan.mcpConfigJSON) else { return }
        configURL = url
        spawn(executablePath: executablePath, args: plan.arguments(mcpConfigPath: url.path))
    }

    /// Resume the paused run with the user's answer (same session + flags).
    func reply(_ text: String) {
        guard case .awaitingInput = state,
              let plan = currentPlan else { return }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        prepareMirroirConfigForSpawn(serverName: plan.serverName)
        if plan.backend.isAPI {
            guard case .available = backendAvailability(plan.backend) else {
                if case let .missing(hint) = backendAvailability(plan.backend) { fail(hint) }
                return
            }
            pendingQuestion = nil
            state = .running
            currentAction = "Resuming…"
            log.append("You: \(answer)")
            startAPI(plan: plan, prompt: answer, priorMessages: apiMessages)
            return
        }
        guard let url = configURL else { return }
        // The CLI rotates session_id on every --resume. If we never captured a
        // (non-empty) id, a resume would attach to the wrong/no conversation —
        // fail the run with a clear message instead of spawning a bad resume.
        guard Self.canResume(sessionId: sessionId), let session = sessionId else {
            cleanupConfig()
            fail(Self.lostSessionMessage)
            return
        }
        let backendStatus = backendAvailability(plan.backend)
        guard case let .available(path: executablePath) = backendStatus else {
            if case let .missing(hint) = backendStatus { fail(hint) }
            return
        }
        pendingQuestion = nil
        state = .running
        currentAction = "Resuming…"
        log.append("You: \(answer)")

        let args = plan.resumeArguments(sessionId: session, reply: answer,
                                        mcpConfigPath: url.path)
        spawn(executablePath: executablePath, args: args)
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
            fail("Failed to launch \(currentPlan?.backend.rawValue ?? "agent"): \(error)")
            cleanupConfig()
        }
    }

    private func startAPI(plan: AutomationPlan, prompt: String,
                          priorMessages: [LLMMessage]) {
        let runtime: ApiAgentRuntime
        do {
            runtime = try apiRuntimeFactory(plan.backend, plan)
        } catch {
            fail(error.localizedDescription)
            return
        }
        apiTask = Task { [weak self] in
            let result = await runtime.run(
                systemPreamble: plan.systemPreamble,
                prompt: prompt,
                priorMessages: priorMessages,
                maxToolCalls: plan.maxTurns,
                serverName: plan.serverName,
                onEvent: { [weak self] event in
                    await self?.handle(event: event)
                }
            )
            guard let self, !Task.isCancelled else { return }
            self.apiMessages = result.messages
            self.finishAPI(result.outcome)
        }
    }

    private func finishAPI(_ outcome: ApiAgentOutcome) {
        apiTask = nil
        switch outcome {
        case .completed:
            state = .finished
            currentAction = "Finished"
            lastCapture = currentCapture
            recordHistory(.finished)
        case .needsInput(let question):
            state = .awaitingInput(question: question)
            currentAction = "Needs input"
        case .failed(let message):
            state = .failed(message)
            currentAction = "Failed"
            recordHistory(.failed)
        case .maxStepsReached:
            state = .failed("Step limit reached.")
            currentAction = "Failed"
            recordHistory(.failed)
        case .cancelled:
            if case .running = state {
                state = .stopped
                recordHistory(.stopped)
            }
        }
    }

    /// Rewrite rough text into a clear phone-automation goal. Text-only spawn —
    /// NO tools, NO --mcp-config. Returns the rewritten goal. Throws on failure;
    /// callers leave the original text unchanged on error.
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
        let out = (String(data: result.stdout, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw RefineError.emptyOutput }
        return out
    }

    func condense(goal: String, rawSteps: [AutomationStep],
                  backend: AgentBackend) async throws -> [AutomationStep] {
        guard !isBusy else { throw CondenseError.backend("A device run is active.") }
        guard case let .available(path) = backendAvailability(backend) else {
            if case let .missing(hint) = backendAvailability(backend) {
                throw CondenseError.backend(hint)
            }
            throw CondenseError.backend("\(backend.rawValue) is unavailable.")
        }
        let prompt = try CondensePrompt.prompt(goal: goal, rawSteps: rawSteps)
        isCondensing = true
        defer { isCondensing = false }

        if backend.isAPI {
            let text = try await apiTextCompletion(backend, prompt)
            return try CondensePrompt.parseResponse(text)
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
        let output = String(decoding: result.stdout, as: UTF8.self)
        return try CondensePrompt.parseResponse(output)
    }

    /// Clear a finished/stopped/failed run from the UI and return to the list.
    func dismissResult() {
        guard !isBusy else { return }
        cleanupConfig() // defensive: no-op if already cleaned; prevents temp-file leaks
        historyContext = nil
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
        // A paused (awaitingInput) run has no live process — its exit already
        // fired and returned early WITHOUT cleaning up the temp config (it was
        // preserved for a resume). Stopping here means no future exit will run
        // cleanupConfig, so do it now to avoid leaking the temp mcp-config file.
        let wasAwaitingInput = isAwaitingInput
        apiTask?.cancel()
        apiTask = nil
        process?.stop()
        if isBusy {
            state = .stopped
            currentAction = "Stopped"
            pendingQuestion = nil
            log.append("— Stopped by user —")
            recordHistory(.stopped)
        }
        if wasAwaitingInput {
            cleanupConfig()
        }
    }

    // MARK: - Stream handling

    private func handle(line: String) {
        guard let backend = currentPlan?.backend else { return }
        handle(event: parseStreamLine(line, backend: backend))
    }

    private func handle(event: StreamEvent) {
        // Capture the session id whenever it's advertised. The CLI rotates the
        // id on `--resume`, and a resumed run may only re-advertise it on the
        // final `result` event (not the init `system` event), so we update the
        // stored id from BOTH event types whenever a non-empty id is observed.
        if case let .system(_, sid) = event, let sid, !sid.isEmpty {
            sessionId = sid
        }
        if case let .result(_, _, sid) = event, let sid, !sid.isEmpty {
            sessionId = sid
        }
        // Remember a pending question; the pause is settled on process exit.
        if case let .needInput(question) = event {
            pendingQuestion = question
        }
        if case let .toolUse(name, _, rawInput) = event {
            currentCapture.append(CapturedCall(tool: name, rawInput: rawInput))
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
            // History already recorded in stop().
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
                lastCapture = currentCapture
                recordHistory(.finished)
            } else {
                let backend = currentPlan?.backend.rawValue ?? "agent"
                let msg = reason.isEmpty ? "\(backend) exited with code \(code)" : "\(backend) \(reason)"
                state = .failed(msg)
                currentAction = "Failed"
                log.append(msg)
                recordHistory(.failed)
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
        recordHistory(.failed)
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

    /// User-facing message when a paused run can't be resumed (no captured id).
    static let lostSessionMessage = "Lost session — start the goal again."

    /// Pure guard for `reply(_:)`: a resume is only safe with a non-empty
    /// session id. The CLI rotates session_id on each `--resume`, so an empty /
    /// nil id means we'd attach to the wrong or no conversation. Unit-testable
    /// without spawning a process.
    static func canResume(sessionId: String?) -> Bool {
        guard let id = sessionId else { return false }
        return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clearCapture() {
        lastCapture = []
    }

}
