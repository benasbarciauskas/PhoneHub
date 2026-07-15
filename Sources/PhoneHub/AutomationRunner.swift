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
        case failed(String)
        case finished
    }

    private(set) var state: RunState = .idle
    private(set) var log: [String] = []
    private(set) var runningAutomationID: UUID?
    var backend: AgentBackend = .claude

    private let store: AutomationStore
    private let agentEngine: AutomationEngine
    private var task: Task<Void, Never>?
    private var client: McpDirectClient?
    private var runToken: UUID?

    init(store: AutomationStore, agentEngine: AutomationEngine) {
        self.store = store
        self.agentEngine = agentEngine
    }

    var isBusy: Bool {
        if case .running = state { return true }
        return false
    }

    func run(_ automation: Automation, on device: Device, othersBusy: Bool) {
        guard !isBusy else { return }
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
        client?.stop()
        client = nil
        if agentEngine.isBusy { agentEngine.stop() }
        if isBusy {
            log.append("— Stopped by user —")
            state = .idle
        }
    }

    func clearResult() {
        guard !isBusy else { return }
        state = .idle
        log = []
        runningAutomationID = nil
    }

    private func execute(_ original: Automation, on device: Device, token: UUID) async {
        var automation = original
        let connection = makeClient(for: device.platform)
        client = connection
        defer {
            connection.stop()
            if client === connection { client = nil }
            if runToken == token { task = nil; runToken = nil }
        }

        do {
            try await connection.start()
            let steps = stepsToRun(automation: automation)
            guard !steps.isEmpty else { state = .finished; return }
            var iteration = 0
            while true {
                for (index, step) in steps.enumerated() {
                    try Task.checkCancellation()
                    state = .running(stepIndex: index, iteration: iteration)
                    log.append("\(index + 1). \(summary(for: step))")

                    if let label = probeLabel(for: step), !automation.sharedCoordinates {
                        let arguments = describeArguments(for: device)
                        let screen = try await connection.callTool("describe_screen",
                                                                   arguments: arguments,
                                                                   timeoutSeconds: 20)
                        if screen.isError { throw RunnerError.tool(screen.text) }
                        let stored = automation.bindings[device.id]?[step.id.uuidString]
                        switch probe(step: label, stored: stored,
                                     elements: parseScreenElements(screen.text)) {
                        case .keep(let binding):
                            try await invoke(step, binding: binding, device: device, client: connection)
                        case .rebind(let binding):
                            automation.bindings[device.id, default: [:]][step.id.uuidString] = binding
                            store.update(automation)
                            log.append("Rebound “\(label)” to (\(Int(binding.x)), \(Int(binding.y))).")
                            try await invoke(step, binding: binding, device: device, client: connection)
                        case .missing:
                            state = .pausedNeedsRecalibrate(stepIndex: index, label: label)
                            log.append("Couldn’t find “\(label)”.")
                            return
                        }
                    } else if case let .wait(_, ms) = step {
                        try await sleep(milliseconds: ms)
                    } else if case let .aiStep(_, prompt) = step {
                        try await runAIStep(prompt, on: device)
                    } else {
                        let binding = automation.sharedCoordinates
                            ? sharedBinding(for: step, in: automation) : nil
                        try await invoke(step, binding: binding, device: device, client: connection)
                    }
                    try await sleep(milliseconds: automationSettleMilliseconds)
                }
                guard let next = nextIteration(loop: automation.loop, current: iteration) else { break }
                iteration = next
            }
            if runToken == token {
                state = .finished
                log.append("Finished.")
            }
        } catch is CancellationError {
            if runToken == token, isBusy { state = .idle }
        } catch {
            if runToken == token { fail(error.localizedDescription) }
        }
    }

    private func invoke(_ step: AutomationStep, binding: Automation.Binding?, device: Device,
                        client: McpDirectClient) async throws {
        guard let invocation = try toolInvocation(for: step, platform: device.platform,
                                                  serial: device.platform == .android ? device.id : nil,
                                                  binding: binding) else { return }
        let arguments = invocation.arguments.mapValues(\.anyValue)
        let result = try await client.callTool(invocation.tool, arguments: arguments, timeoutSeconds: 30)
        if result.isError { throw RunnerError.tool(result.text) }
    }

    private func runAIStep(_ prompt: String, on device: Device) async throws {
        agentEngine.runAdhoc(goal: prompt, on: device, backend: backend)
        while agentEngine.isBusy {
            if agentEngine.isAwaitingInput { throw RunnerError.ai("AI step needs input.") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        switch agentEngine.state {
        case .finished: return
        case .failed(let message): throw RunnerError.ai(message)
        case .stopped: throw CancellationError()
        default: throw RunnerError.ai("AI step did not finish.")
        }
    }

    private func makeClient(for platform: Platform) -> McpDirectClient {
        let packageArguments: [String]
        switch platform {
        case .ios: packageArguments = ["-y", "mirroir-mcp", "--dangerously-skip-permissions"]
        case .android: packageArguments = ["-y", "androir-mcp"]
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
        }
    }

    private func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private func fail(_ message: String) {
        state = .failed(message)
        log.append(message)
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
