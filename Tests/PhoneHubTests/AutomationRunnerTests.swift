import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class AutomationRunnerTests: XCTestCase {
    private let device = Device(
        id: "test-ios",
        platform: .ios,
        model: "iPhone",
        osVersion: "18",
        status: "connected"
    )

    func testRefreshFailureFailsRunBeforePhoneClientAndSkipsSuccessHook() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let stepID = UUID()
        var source = try harness.textSources.add(
            name: "Captions", items: ["stale"], mode: .cycle
        )
        source.refreshCommand = "refresh"
        harness.textSources.update(source)
        let automation = Automation(
            name: "Post",
            platform: .ios,
            steps: [.typeText(id: stepID, text: "fallback")],
            textSourceBindings: [stepID: TextSourceRef(sourceID: source.id)],
            onSuccessCommand: "after"
        )
        var commands: [String] = []
        harness.runner.commandRunner = { command, _ in
            commands.append(command)
            return CommandResult(exitCode: 7, stdout: Data(), stderr: "refresh broke")
        }

        harness.runner.run(automation, on: device, othersBusy: false)
        try await waitUntil { if case .failed = harness.runner.state { true } else { false } }

        XCTAssertEqual(commands, ["refresh"])
        XCTAssertFalse(harness.client.started)
        XCTAssertEqual(harness.history.records(deviceId: device.id).first?.outcome, .failed)
        XCTAssertTrue(harness.runner.log.last?.contains("refresh broke") == true)
    }

    func testSuccessCommandRunsAfterSuccessfulAutomationAndIsRecordedInHistory() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let automation = Automation(
            name: "Post",
            platform: .ios,
            steps: [],
            onSuccessCommand: "after"
        )
        var commands: [String] = []
        var hookContinuation: CheckedContinuation<CommandResult, Error>?
        harness.runner.commandRunner = { command, timeout in
            commands.append(command)
            XCTAssertEqual(timeout, 30)
            return try await withCheckedThrowingContinuation { hookContinuation = $0 }
        }

        harness.runner.run(automation, on: device, othersBusy: false)
        try await waitUntil { hookContinuation != nil }

        XCTAssertEqual(harness.runner.state, .finished, "The hook must not keep the run busy")
        XCTAssertTrue(harness.history.records(deviceId: device.id).isEmpty)

        hookContinuation?.resume(returning: CommandResult(
            exitCode: 0,
            stdout: Data("posted 42\nignored".utf8),
            stderr: ""
        ))
        try await waitUntil { !harness.history.records(deviceId: self.device.id).isEmpty }

        XCTAssertEqual(commands, ["after"])
        let record = try XCTUnwrap(harness.history.records(deviceId: device.id).first)
        XCTAssertEqual(record.outcome, .finished)
        XCTAssertTrue(record.log.contains("On-success command exited 0: posted 42"))
    }

    func testSuccessCommandDoesNotRunWhenAutomationStepFails() async throws {
        let harness = try makeHarness(toolResult: McpToolResult(text: "tap failed", isError: true))
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let automation = Automation(
            name: "Failing",
            platform: .ios,
            steps: [.pressHome(id: UUID())],
            onSuccessCommand: "after"
        )
        var commands: [String] = []
        harness.runner.commandRunner = { command, _ in
            commands.append(command)
            return CommandResult(exitCode: 0, stdout: Data(), stderr: "")
        }

        harness.runner.run(automation, on: device, othersBusy: false)
        try await waitUntil { if case .failed = harness.runner.state { true } else { false } }

        XCTAssertTrue(commands.isEmpty)
        XCTAssertEqual(harness.history.records(deviceId: device.id).first?.outcome, .failed)
    }

    func testNonzeroSuccessCommandIsRecordedWithoutFailingAutomation() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let automation = Automation(
            name: "Post",
            platform: .ios,
            steps: [],
            onSuccessCommand: "after"
        )
        harness.runner.commandRunner = { _, _ in
            CommandResult(exitCode: 9, stdout: Data(), stderr: "hook broke\nmore detail")
        }

        harness.runner.run(automation, on: device, othersBusy: false)
        try await waitUntil { !harness.history.records(deviceId: self.device.id).isEmpty }

        XCTAssertEqual(harness.runner.state, .finished)
        let record = try XCTUnwrap(harness.history.records(deviceId: device.id).first)
        XCTAssertEqual(record.outcome, .finished)
        XCTAssertTrue(record.log.contains("On-success command exited 9: hook broke"))
    }

    func testCancelDuringRefreshDoesNotMutateSourceStartPhoneOrRunSuccessHook() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let stepID = UUID()
        var source = try harness.textSources.add(
            name: "Captions", items: ["stale"], mode: .cycle
        )
        source.refreshCommand = "refresh"
        harness.textSources.update(source)
        let automation = Automation(
            name: "Post",
            platform: .ios,
            steps: [.typeText(id: stepID, text: "fallback")],
            textSourceBindings: [stepID: TextSourceRef(sourceID: source.id)],
            onSuccessCommand: "after"
        )
        var commands: [String] = []
        var refreshContinuation: CheckedContinuation<CommandResult, Error>?
        harness.runner.commandRunner = { command, _ in
            commands.append(command)
            return try await withCheckedThrowingContinuation { refreshContinuation = $0 }
        }

        harness.runner.run(automation, on: device, othersBusy: false)
        try await waitUntil { refreshContinuation != nil }
        harness.runner.stop()
        refreshContinuation?.resume(returning: CommandResult(
            exitCode: 0,
            stdout: Data(#"["fresh"]"#.utf8),
            stderr: ""
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.runner.state, .idle)
        XCTAssertEqual(harness.textSources.sources.first?.items, ["stale"])
        XCTAssertFalse(harness.client.started)
        XCTAssertEqual(commands, ["refresh"])
        XCTAssertEqual(harness.history.records(deviceId: device.id).first?.outcome, .stopped)
    }

    private func makeHarness(
        toolResult: McpToolResult = McpToolResult(text: "ok", isError: false)
    ) throws -> (
        directory: URL,
        textSources: TextSourceStore,
        history: RunHistoryStore,
        client: RunnerMCPClient,
        runner: AutomationRunner
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutomationRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let textSources = TextSourceStore(directory: directory.appendingPathComponent("sources"))
        let history = RunHistoryStore(directory: directory.appendingPathComponent("history"))
        let engine = AutomationEngine(backendAvailability: { _ in .missing(hint: "unused") })
        engine.commandGate = { _ in nil }
        let runner = AutomationRunner(
            store: AutomationStore(directory: directory.appendingPathComponent("automations")),
            agentEngine: engine,
            textSourceStore: textSources
        )
        runner.commandGate = { _ in nil }
        runner.runHistoryStore = history
        let client = RunnerMCPClient(result: toolResult)
        runner.mcpClientFactory = { _ in client }
        return (directory, textSources, history, client, runner)
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !predicate() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(predicate())
    }
}

private final class RunnerMCPClient: McpToolClient, @unchecked Sendable {
    private let result: McpToolResult
    private(set) var started = false

    init(result: McpToolResult) { self.result = result }

    func start() async throws { started = true }

    func callTool(_ name: String, arguments: [String: Any],
                  timeoutSeconds: Double) async throws -> McpToolResult {
        result
    }

    func stop() {}
}
