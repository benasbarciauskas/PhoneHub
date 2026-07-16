import Foundation
import Observation
import PhoneHubCore

/// App-open-only schedule driver. Polls with a `Timer` while the app is running;
/// never uses launchd. Respects the three-way run-slot exclusion (preset / automation / chat).
@Observable
@MainActor
final class SchedulerRunner {
    private let scheduleStore: ScheduleStore
    private let presetStore: PresetStore
    private let automationStore: AutomationStore
    private let deviceStore: DeviceStore
    private let engine: AutomationEngine
    private let automationRunner: AutomationRunner
    private let chatEngine: ChatEngine
    private let historyStore: RunHistoryStore
    private let backendProvider: () -> AgentBackend
    private let preferKnownStepsProvider: () -> Bool

    private var timer: Timer?
    private let pollInterval: TimeInterval

    init(
        scheduleStore: ScheduleStore,
        presetStore: PresetStore,
        automationStore: AutomationStore,
        deviceStore: DeviceStore,
        engine: AutomationEngine,
        automationRunner: AutomationRunner,
        chatEngine: ChatEngine,
        historyStore: RunHistoryStore,
        backendProvider: @escaping () -> AgentBackend,
        preferKnownStepsProvider: @escaping () -> Bool = { false },
        pollInterval: TimeInterval = 15
    ) {
        self.scheduleStore = scheduleStore
        self.presetStore = presetStore
        self.automationStore = automationStore
        self.deviceStore = deviceStore
        self.engine = engine
        self.automationRunner = automationRunner
        self.chatEngine = chatEngine
        self.historyStore = historyStore
        self.backendProvider = backendProvider
        self.preferKnownStepsProvider = preferKnownStepsProvider
        self.pollInterval = pollInterval
    }

    var isRunning: Bool { timer != nil }

    /// Begin polling. Idempotent.
    func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Allow firing while UI tracking is active (menus, scrolling).
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Catch up soon after launch without waiting a full interval.
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Evaluate due schedules once. Public for tests.
    func tick(now: Date = .now) {
        // Snapshot so markFired mutations don't skip remaining entries.
        let due = scheduleStore.schedules.filter {
            Scheduler.isDue($0, now: now, lastFired: $0.lastFired)
        }
        for schedule in due {
            fire(schedule, at: now)
        }
    }

    private var slotBusy: Bool {
        engine.isBusy || automationRunner.isBusy || chatEngine.isBusy
    }

    private func fire(_ schedule: Schedule, at now: Date) {
        // Consume this firing even on skip so we don't spin every poll while busy.
        scheduleStore.markFired(schedule, at: now)

        if slotBusy {
            appendSkip(schedule, reason: "skipped (busy)", at: now)
            return
        }

        guard let device = deviceStore.devices.first(where: { $0.id == schedule.deviceId }) else {
            appendSkip(schedule, reason: "skipped (device offline)", at: now)
            return
        }

        switch schedule.targetKind {
        case .preset:
            guard let preset = presetStore.presets.first(where: { $0.id == schedule.targetId }) else {
                appendSkip(schedule, reason: "skipped (preset missing)", at: now)
                return
            }
            engine.run(preset: preset, on: device, backend: backendProvider(),
                       preferKnownSteps: preferKnownStepsProvider())
        case .automation:
            guard let automation = automationStore.automations.first(where: { $0.id == schedule.targetId }) else {
                appendSkip(schedule, reason: "skipped (automation missing)", at: now)
                return
            }
            let othersBusy = engine.isBusy || chatEngine.isBusy
            automationRunner.backend = backendProvider()
            automationRunner.preferKnownSteps = preferKnownStepsProvider()
            automationRunner.run(automation, on: device, othersBusy: othersBusy)
        }
    }

    private func appendSkip(_ schedule: Schedule, reason: String, at now: Date) {
        historyStore.append(
            RunRecord(
                name: schedule.name,
                kind: schedule.targetKind,
                deviceId: schedule.deviceId,
                deviceName: schedule.deviceName,
                startedAt: now,
                endedAt: now,
                outcome: .stopped,
                log: [reason]
            ),
            deviceId: schedule.deviceId
        )
    }
}
