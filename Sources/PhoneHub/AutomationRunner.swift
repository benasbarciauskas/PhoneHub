import Foundation
import Observation
import PhoneHubCore

@Observable
@MainActor
final class AutomationRunner {
    enum RunState: Equatable {
        case idle
        case running(stepIndex: Int, iteration: Int)
        case pausedNeedsRecalibrate(stepIndex: Int, label: String)
        case pausedNeedsDevice(stepIndex: Int, deviceRef: String)
        case failed(String)
        case finished
    }

    private(set) var state: RunState = .idle
    private(set) var log: [String] = []
    private(set) var runningAutomationID: UUID?
    var backend: AgentBackend = .claude
    var preferKnownSteps: Bool = false

    /// Optional; when set, every terminal automation run is appended to per-device history.
    var runHistoryStore: RunHistoryStore?

    /// Resolve a switchDevice ref to a currently connected device (wired from DeviceStore).
    var deviceResolver: (String) -> Device? = { _ in nil }

    private let store: AutomationStore
    private let textSourceStore: TextSourceStore
    private let agentEngine: AutomationEngine
    private var task: Task<Void, Never>?
    private var client: McpDirectClient?
    private var runToken: UUID?
    private var historyContext: HistoryContext?

    private struct HistoryContext {
        let name: String
        let deviceId: String
        let deviceName: String
        let startedAt: Date
    }

    init(store: AutomationStore, agentEngine: AutomationEngine,
         textSourceStore: TextSourceStore? = nil) {
        self.store = store
        self.agentEngine = agentEngine
        self.textSourceStore = textSourceStore ?? TextSourceStore()
    }

    var isBusy: Bool {
        switch state {
        case .running, .pausedNeedsDevice: return true
        default: return false
        }
    }

    func run(_ automation: Automation, on device: Device, othersBusy: Bool) {
        guard !isBusy else { return }
        log = []
        beginHistory(name: automation.name, device: device)
        guard !othersBusy else { fail("Another automation or chat is active."); return }
        guard automation.platform == device.platform else {
            fail("This automation is for \(automation.platform.rawValue), not \(device.platform.rawValue).")
            return
        }
        if device.platform == .android, !isValidSerial(device.id) {
            fail("Invalid Android device serial.")
            return
        }

        log = ["Running “\(automation.name)” on \(device.model)…"]
        runningAutomationID = automation.id
        state = .running(stepIndex: 0, iteration: 0)
        let token = UUID()
        runToken = token
        task = Task { [weak self] in
            await self?.execute(automation, on: device, token: token)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        runToken = nil
        stopClient()
        if agentEngine.isBusy { agentEngine.stop() }
        if case .running = state {
            log.append("— Stopped by user —")
            state = .idle
            recordHistory(.stopped)
        } else if case .pausedNeedsDevice = state {
            log.append("— Stopped by user —")
            state = .idle
            recordHistory(.stopped)
        }
    }

    func clearResult() {
        guard !isBusy else { return }
        historyContext = nil
        state = .idle
        log = []
        runningAutomationID = nil
    }

    private func execute(_ original: Automation, on device: Device, token: UUID) async {
        var automation = original
        var currentDevice = device
        defer {
            stopClient()
            if runToken == token { task = nil; runToken = nil }
        }

        do {
            // Bind each source once at run start. Cycle cursors are committed only
            // after every iteration succeeds, so failed and cancelled runs consume nothing.
            let textResolution = try textSourceStore.resolve(automation)
            automation.steps = textResolution.steps
            let initial = makeClient(for: currentDevice.platform)
            client = initial
            try await initial.start()
            let steps = stepsToRun(automation: automation)
            guard !steps.isEmpty else {
                if runToken == token {
                    state = .finished
                    recordHistory(.finished)
                }
                return
            }
            var iteration = 0
            while true {
                for (index, step) in steps.enumerated() {
                    try Task.checkCancellation()
                    state = .running(stepIndex: index, iteration: iteration)
                    log.append("\(index + 1). \(summary(for: step))")

                    if case let .switchDevice(_, deviceRef) = step {
                        guard let next = deviceResolver(deviceRef) else {
                            let message = "Device '\(deviceRef)' not connected — connect it to continue"
                            state = .pausedNeedsDevice(stepIndex: index, deviceRef: deviceRef)
                            log.append(message)
                            stopClient()
                            return
                        }
                        if next.platform == .android, !isValidSerial(next.id) {
                            throw RunnerError.tool("Invalid Android device serial.")
                        }
                        try await switchTo(next)
                        currentDevice = next
                        log.append("Switched to \(next.model) (\(next.platform.rawValue)).")
                        continue
                    }

                    guard let connection = client else {
                        throw RunnerError.tool("MCP client is not running.")
                    }

                    if let label = probeLabel(for: step), !automation.sharedCoordinates {
                        let arguments = describeArguments(for: currentDevice)
                        let screen = try await connection.callTool("describe_screen",
                                                                   arguments: arguments,
                                                                   timeoutSeconds: 20)
                        if screen.isError { throw RunnerError.tool(screen.text) }
                        let stored = automation.bindings[currentDevice.id]?[step.id.uuidString]
                        switch probe(step: label, stored: stored,
                                     elements: parseScreenElements(screen.text)) {
                        case .keep(let binding):
                            try await invoke(step, binding: binding, device: currentDevice, client: connection)
                        case .rebind(let binding):
                            automation.bindings[currentDevice.id, default: [:]][step.id.uuidString] = binding
                            store.update(automation)
                            log.append("Rebound “\(label)” to (\(Int(binding.x)), \(Int(binding.y))).")
                            try await invoke(step, binding: binding, device: currentDevice, client: connection)
                        case .missing:
                            state = .pausedNeedsRecalibrate(stepIndex: index, label: label)
                            log.append("Couldn’t find “\(label)”.")
                            return
                        }
                    } else if case let .wait(_, ms) = step {
                        try await sleep(milliseconds: ms)
                    } else if case let .aiStep(_, prompt) = step {
                        try await runAIStep(prompt, on: currentDevice)
                    } else {
                        let binding = automation.sharedCoordinates
                            ? sharedBinding(for: step, in: automation) : nil
                        try await invoke(step, binding: binding, device: currentDevice, client: connection)
                    }
                    try await sleep(milliseconds: automationSettleMilliseconds)
                }
                guard let next = nextIteration(loop: automation.loop, current: iteration) else { break }
                iteration = next
            }
            if runToken == token {
                log.append(contentsOf: textSourceStore.commit(textResolution))
                state = .finished
                log.append("Finished.")
                recordHistory(.finished)
            }
        } catch is CancellationError {
            // stop() records .stopped; only clear busy if still running under this token.
            if runToken == token, isBusy { state = .idle }
        } catch {
            if runToken == token { fail(error.localizedDescription) }
        }
    }

    private func switchTo(_ device: Device) async throws {
        stopClient()
        let next = makeClient(for: device.platform)
        client = next
        try await next.start()
    }

    private func stopClient() {
        client?.stop()
        client = nil
    }

    private func invoke(_ step: AutomationStep, binding: Automation.Binding?, device: Device,
                        client: McpDirectClient) async throws {
        // Use the *current* device platform (may differ from automation.platform after switchDevice).
        guard let invocation = try toolInvocation(for: step, platform: device.platform,
                                                  serial: device.platform == .android ? device.id : nil,
                                                  binding: binding) else { return }
        let arguments = invocation.arguments.mapValues(\.anyValue)
        let result = try await client.callTool(invocation.tool, arguments: arguments, timeoutSeconds: 30)
        if result.isError { throw RunnerError.tool(result.text) }
    }

    private func runAIStep(_ prompt: String, on device: Device) async throws {
        agentEngine.runAdhoc(goal: prompt, on: device, backend: backend,
                             preferKnownSteps: preferKnownSteps)
        while agentEngine.isBusy {
            if agentEngine.isAwaitingInput { throw RunnerError.ai("AI step needs input.") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        switch agentEngine.state {
        case .finished:
            agentEngine.clearCapture()
            agentEngine.dismissResult()
            return
        case .failed(let message): throw RunnerError.ai(message)
        case .stopped: throw CancellationError()
        default: throw RunnerError.ai("AI step did not finish.")
        }
    }

    private func makeClient(for platform: Platform) -> McpDirectClient {
        let packageArguments: [String]
        switch platform {
        case .ios:
            prepareMirroirConfigForSpawn(serverName: "mirroir")
            packageArguments = ["-y", "mirroir-mcp", "--dangerously-skip-permissions"]
        case .android:
            packageArguments = ["-y", "androir-mcp"]
        }
        if let npx = resolveTool("npx") {
            return McpDirectClient(command: npx, arguments: packageArguments)
        }
        return McpDirectClient(command: "/usr/bin/env", arguments: ["npx"] + packageArguments)
    }

    private func describeArguments(for device: Device) -> [String: Any] {
        device.platform == .android ? ["serial": device.id] : [:]
    }

    private func sharedBinding(for step: AutomationStep, in automation: Automation) -> Automation.Binding? {
        for deviceBindings in automation.bindings.values {
            if let binding = deviceBindings[step.id.uuidString] { return binding }
        }
        return nil
    }

    private func probeLabel(for step: AutomationStep) -> String? {
        switch step {
        case let .tap(_, label, _, _), let .doubleTap(_, label, _, _),
             let .longPress(_, label, _, _, _): return label
        default: return nil
        }
    }

    private func summary(for step: AutomationStep) -> String {
        switch step {
        case .launchApp: return "Launch app"
        case .tap: return "Tap"
        case .doubleTap: return "Double tap"
        case .longPress: return "Long press"
        case .typeText: return "Type text"
        case .pressKey: return "Press key"
        case .swipe: return "Swipe"
        case .pressHome: return "Press Home"
        case .pressBack: return "Press Back"
        case .pressAppSwitcher: return "Press App Switcher"
        case .scrollTo: return "Scroll to text"
        case .openURL: return "Open URL"
        case .wait: return "Wait"
        case .aiStep: return "AI step"
        case let .switchDevice(_, deviceRef): return "Switch device → \(deviceRef)"
        }
    }

    private func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private func fail(_ message: String) {
        state = .failed(message)
        log.append(message)
        recordHistory(.failed)
    }

    private func beginHistory(name: String, device: Device) {
        historyContext = HistoryContext(
            name: name,
            deviceId: device.id,
            deviceName: device.model,
            startedAt: .now
        )
    }

    private func recordHistory(_ outcome: RunOutcome) {
        guard let ctx = historyContext else { return }
        historyContext = nil
        guard let store = runHistoryStore else { return }
        store.append(
            RunRecord(
                name: ctx.name,
                kind: .automation,
                deviceId: ctx.deviceId,
                deviceName: ctx.deviceName,
                startedAt: ctx.startedAt,
                endedAt: .now,
                outcome: outcome,
                log: log
            ),
            deviceId: ctx.deviceId
        )
    }
}

private enum RunnerError: Error, LocalizedError {
    case tool(String)
    case ai(String)
    var errorDescription: String? {
        switch self {
        case .tool(let message): return message.isEmpty ? "Phone tool failed." : message
        case .ai(let message): return message
        }
    }
}
