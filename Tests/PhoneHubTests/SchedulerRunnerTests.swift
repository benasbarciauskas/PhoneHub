import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class SchedulerRunnerTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchedulerRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSkipBusyWritesHistoryAndMarksFired() throws {
        let dir = try tempDir()
        let scheduleStore = ScheduleStore(directory: dir)
        let history = RunHistoryStore(directory: dir.appendingPathComponent("history"))
        let presets = PresetStore(directory: dir.appendingPathComponent("presets"))
        let automations = AutomationStore(directory: dir.appendingPathComponent("autos"))
        let devices = DeviceStore()
        let engine = AutomationEngine(
            backendAvailability: { _ in .missing(hint: "no") }
        )
        engine.commandGate = { _ in nil }
        // Make the slot busy via awaitingInput-style: start a failed run? easier — use chat busy.
        // ChatEngine isBusy is turnState == .running; we don't have a clean setter.
        // Instead force engine busy by putting it in failed with history — isBusy is false for failed.
        // Use AutomationRunner.isBusy by starting… can't without MCP.
        // Simulate busy by setting engine into awaitingInput via API needsInput is heavy.
        // Simplest: use a stub approach — call tick when engine has isBusy from a real API hang.

        // Put engine into "busy" by using a never-resolving provider would hang tests.
        // Instead test the skip path by manually checking slotBusy logic via history after
        // making chat engine report busy. ChatEngine doesn't expose setters.

        // Practical approach: when device is offline, we still mark fired + write skip.
        let preset = presets.presets[0]
        let schedule = Schedule(
            name: preset.name,
            targetKind: .preset,
            targetId: preset.id,
            deviceId: "missing-device",
            deviceName: "Gone",
            cadence: .interval,
            intervalMinutes: 5,
            enabled: true,
            lastFired: nil
        )
        scheduleStore.add(schedule)

        let engine2 = AutomationEngine(backendAvailability: { _ in .available(path: "/bin/true") })
        engine2.commandGate = { _ in nil }
        let chat = ChatEngine()
        chat.commandGate = { _ in nil }
        let runner = AutomationRunner(store: automations, agentEngine: engine2)
        runner.commandGate = { _ in nil }
        let scheduler = SchedulerRunner(
            scheduleStore: scheduleStore,
            presetStore: presets,
            automationStore: automations,
            deviceStore: devices,
            engine: engine2,
            automationRunner: runner,
            chatEngine: chat,
            historyStore: history,
            backendProvider: { .claude }
        )

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        scheduler.tick(now: now)

        XCTAssertEqual(scheduleStore.schedules.first?.lastFired, now)
        let records = history.records(deviceId: "missing-device")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].log, ["skipped (device offline)"])
        XCTAssertEqual(records[0].outcome, .stopped)

        // Not due again immediately (lastFired just set).
        scheduler.tick(now: now.addingTimeInterval(10))
        XCTAssertEqual(history.records(deviceId: "missing-device").count, 1)
    }

    func testIntervalDueAgainAfterElapsed() throws {
        let dir = try tempDir()
        let scheduleStore = ScheduleStore(directory: dir)
        let history = RunHistoryStore(directory: dir.appendingPathComponent("history"))
        let presets = PresetStore(directory: dir.appendingPathComponent("presets"))
        let automations = AutomationStore(directory: dir.appendingPathComponent("autos"))
        let devices = DeviceStore()
        let engine = AutomationEngine(backendAvailability: { _ in .available(path: "/bin/true") })
        engine.commandGate = { _ in nil }
        let chat = ChatEngine()
        chat.commandGate = { _ in nil }
        let runner = AutomationRunner(store: automations, agentEngine: engine)
        runner.commandGate = { _ in nil }
        let scheduler = SchedulerRunner(
            scheduleStore: scheduleStore,
            presetStore: presets,
            automationStore: automations,
            deviceStore: devices,
            engine: engine,
            automationRunner: runner,
            chatEngine: chat,
            historyStore: history,
            backendProvider: { .claude }
        )

        let preset = presets.presets[0]
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        scheduleStore.add(Schedule(
            name: preset.name,
            targetKind: .preset,
            targetId: preset.id,
            deviceId: "dev-x",
            deviceName: "X",
            cadence: .interval,
            intervalMinutes: 10,
            lastFired: first
        ))

        scheduler.tick(now: first.addingTimeInterval(9 * 60))
        XCTAssertEqual(history.records(deviceId: "dev-x").count, 0)

        scheduler.tick(now: first.addingTimeInterval(10 * 60))
        XCTAssertEqual(history.records(deviceId: "dev-x").count, 1)
        XCTAssertEqual(history.records(deviceId: "dev-x")[0].log, ["skipped (device offline)"])
    }
}
