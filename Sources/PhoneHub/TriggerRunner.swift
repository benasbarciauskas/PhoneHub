import Foundation
import Observation
import PhoneHubCore

/// App-open-only event-trigger driver. Polls Android device state with a `Timer`
/// while the app is running; never uses launchd. Respects the three-way run-slot
/// exclusion (preset / automation / chat).
///
/// Fires **once** per matching notification (seen by package+title+whenMs) and
/// **once** per foreground-ENTER edge. First poll seeds state without firing.
@Observable
@MainActor
final class TriggerRunner {
    private let triggerStore: TriggerStore
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

    /// Per-trigger notification identity keys already observed.
    private var seenNotifications: [UUID: Set<String>] = [:]
    /// Per-trigger last observed foreground package (empty string = none/unknown).
    private var lastForegroundPackage: [UUID: String] = [:]
    /// Triggers that have completed their first poll (seed without fire).
    private var seeded: Set<UUID> = []

    /// Optional injectors for tests (default: live adb readers).
    var notificationFetcher: (String) -> [PhoneNotification] = { NotificationReader.fetch(serial: $0) }
    var foregroundFetcher: (String) -> String? = { ForegroundReader.fetch(serial: $0) }

    init(
        triggerStore: TriggerStore,
        presetStore: PresetStore,
        automationStore: AutomationStore,
        deviceStore: DeviceStore,
        engine: AutomationEngine,
        automationRunner: AutomationRunner,
        chatEngine: ChatEngine,
        historyStore: RunHistoryStore,
        backendProvider: @escaping () -> AgentBackend,
        preferKnownStepsProvider: @escaping () -> Bool = { false },
        pollInterval: TimeInterval = 7
    ) {
        self.triggerStore = triggerStore
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
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Evaluate enabled triggers once. Public for tests.
    func tick(now: Date = .now) {
        let enabled = triggerStore.triggers.filter(\.enabled)
        guard !enabled.isEmpty else { return }

        // Group by device so we poll dumpsys at most once per device per tick.
        let byDevice = Dictionary(grouping: enabled, by: \.deviceId)
        for (deviceId, triggers) in byDevice {
            guard let device = deviceStore.devices.first(where: { $0.id == deviceId }) else {
                for t in triggers {
                    // Device offline: do not consume edges / seed so reconnect can work cleanly.
                    // Still no fire.
                    _ = t
                }
                continue
            }
            guard device.platform == .android else { continue }
            // Only poll ready Android devices.
            guard device.status == "device" || device.isReady else { continue }

            let needsNotif = triggers.contains {
                if case .notificationMatch = $0.condition { return true }
                return false
            }
            let needsFg = triggers.contains {
                if case .appForeground = $0.condition { return true }
                return false
            }

            let notifications = needsNotif ? notificationFetcher(deviceId) : []
            let foreground = needsFg ? foregroundFetcher(deviceId) : nil

            for trigger in triggers {
                evaluate(trigger, device: device, notifications: notifications,
                         foreground: foreground, now: now)
            }
        }

        // Drop runtime state for deleted triggers.
        let liveIds = Set(triggerStore.triggers.map(\.id))
        seenNotifications = seenNotifications.filter { liveIds.contains($0.key) }
        lastForegroundPackage = lastForegroundPackage.filter { liveIds.contains($0.key) }
        seeded = seeded.intersection(liveIds)
    }

    private var slotBusy: Bool {
        engine.isBusy || automationRunner.isBusy || chatEngine.isBusy
    }

    private func evaluate(
        _ trigger: Trigger,
        device: Device,
        notifications: [PhoneNotification],
        foreground: String?,
        now: Date
    ) {
        switch trigger.condition {
        case .notificationMatch(let packageContains, let textContains):
            evaluateNotification(
                trigger, device: device, notifications: notifications,
                packageContains: packageContains, textContains: textContains, now: now
            )
        case .appForeground(let packageContains):
            evaluateForeground(
                trigger, device: device, foreground: foreground,
                packageContains: packageContains, now: now
            )
        }
    }

    private func evaluateNotification(
        _ trigger: Trigger,
        device: Device,
        notifications: [PhoneNotification],
        packageContains: String?,
        textContains: String?,
        now: Date
    ) {
        if !seeded.contains(trigger.id) {
            seenNotifications[trigger.id] = TriggerLogic.seedSeenKeys(notifications)
            seeded.insert(trigger.id)
            return
        }

        var seen = seenNotifications[trigger.id] ?? []
        let news = TriggerLogic.newMatchingNotifications(
            current: notifications,
            seen: seen,
            packageContains: packageContains,
            textContains: textContains
        )
        guard !news.isEmpty else {
            // Still refresh seen with any non-matching newcomers so they don't fire later
            // if filters change? Keep simple: only track keys we observe after seed.
            // Merge all current keys so removed+readded with same key is still "seen"
            // while present; when they drop off the shade and reappear with new whenMs they fire.
            for n in notifications {
                seen.insert(TriggerLogic.notificationSeenKey(n))
            }
            seenNotifications[trigger.id] = seen
            return
        }

        // Mark all new matching as seen immediately (fire-once even if busy skip).
        for n in news {
            seen.insert(TriggerLogic.notificationSeenKey(n))
        }
        for n in notifications {
            seen.insert(TriggerLogic.notificationSeenKey(n))
        }
        seenNotifications[trigger.id] = seen

        // One run per tick max per trigger (first matching new notif).
        fire(trigger, on: device, at: now)
    }

    private func evaluateForeground(
        _ trigger: Trigger,
        device: Device,
        foreground: String?,
        packageContains: String,
        now: Date
    ) {
        let current = foreground ?? ""
        if !seeded.contains(trigger.id) {
            lastForegroundPackage[trigger.id] = current
            seeded.insert(trigger.id)
            return
        }

        let previousRaw = lastForegroundPackage[trigger.id] ?? ""
        let previous: String? = previousRaw.isEmpty ? nil : previousRaw
        let currentOpt: String? = current.isEmpty ? nil : current

        let shouldFire = TriggerLogic.shouldFireForeground(
            previousPackage: previous,
            currentPackage: currentOpt,
            packageContains: packageContains,
            hasPriorObservation: true
        )
        lastForegroundPackage[trigger.id] = current
        guard shouldFire else { return }
        fire(trigger, on: device, at: now)
    }

    private func fire(_ trigger: Trigger, on device: Device, at now: Date) {
        // Record attempt even on skip so UI can show last activity.
        triggerStore.markFired(trigger, at: now)

        if slotBusy {
            appendSkip(trigger, reason: "skipped (busy)", at: now)
            return
        }

        switch trigger.targetKind {
        case .preset:
            guard let preset = presetStore.presets.first(where: { $0.id == trigger.targetId }) else {
                appendSkip(trigger, reason: "skipped (preset missing)", at: now)
                return
            }
            engine.run(preset: preset, on: device, backend: backendProvider(),
                       preferKnownSteps: preferKnownStepsProvider())
        case .automation:
            guard let automation = automationStore.automations.first(where: { $0.id == trigger.targetId }) else {
                appendSkip(trigger, reason: "skipped (automation missing)", at: now)
                return
            }
            let othersBusy = engine.isBusy || chatEngine.isBusy
            automationRunner.backend = backendProvider()
            automationRunner.preferKnownSteps = preferKnownStepsProvider()
            automationRunner.run(automation, on: device, othersBusy: othersBusy)
        }
    }

    private func appendSkip(_ trigger: Trigger, reason: String, at now: Date) {
        historyStore.append(
            RunRecord(
                name: trigger.name,
                kind: trigger.targetKind,
                deviceId: trigger.deviceId,
                deviceName: trigger.deviceName,
                startedAt: now,
                endedAt: now,
                outcome: .stopped,
                log: [reason]
            ),
            deviceId: trigger.deviceId
        )
    }
}
