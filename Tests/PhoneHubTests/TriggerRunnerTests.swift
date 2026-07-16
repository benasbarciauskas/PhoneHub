import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class TriggerRunnerTests: XCTestCase {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TriggerRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeHarness(dir: URL) -> (
        TriggerStore, PresetStore, AutomationStore, DeviceStore,
        RunHistoryStore, TriggerRunner
    ) {
        let triggerStore = TriggerStore(directory: dir)
        let history = RunHistoryStore(directory: dir.appendingPathComponent("history"))
        let presets = PresetStore(directory: dir.appendingPathComponent("presets"))
        let automations = AutomationStore(directory: dir.appendingPathComponent("autos"))
        let devices = DeviceStore()
        let engine = AutomationEngine(backendAvailability: { _ in .available(path: "/bin/true") })
        let chat = ChatEngine()
        let runner = AutomationRunner(store: automations, agentEngine: engine)
        let triggerRunner = TriggerRunner(
            triggerStore: triggerStore,
            presetStore: presets,
            automationStore: automations,
            deviceStore: devices,
            engine: engine,
            automationRunner: runner,
            chatEngine: chat,
            historyStore: history,
            backendProvider: { .claude }
        )
        return (triggerStore, presets, automations, devices, history, triggerRunner)
    }

    /// Missing target → skip path without starting a real engine run.
    private func addMissingTargetTrigger(
        store: TriggerStore,
        deviceId: String,
        condition: TriggerCondition
    ) {
        store.add(Trigger(
            name: "T",
            deviceId: deviceId,
            deviceName: "P",
            targetKind: .preset,
            targetId: UUID(),
            condition: condition
        ))
    }

    func testNotificationFiresOnceForNewAfterSeed() throws {
        let dir = try tempDir()
        let (triggerStore, _, _, devices, history, tr) = makeHarness(dir: dir)
        devices.devices = [
            Device(id: "serial-a", platform: .android, model: "Pixel",
                   osVersion: "14", status: "device")
        ]
        addMissingTargetTrigger(
            store: triggerStore,
            deviceId: "serial-a",
            condition: .notificationMatch(packageContains: "mail", textContains: nil)
        )

        let old = PhoneNotification(package: "com.mail", title: "Hi", text: "x", whenMs: 1)
        let neu = PhoneNotification(package: "com.mail", title: "New", text: "y", whenMs: 2)
        var dumps: [[PhoneNotification]] = [
            [old],           // seed — no fire
            [old, neu],      // new matching → fire once (skip missing preset)
            [old, neu],      // same set → no re-fire
            [old, neu],
        ]
        tr.notificationFetcher = { _ in
            guard !dumps.isEmpty else { return [old, neu] }
            return dumps.removeFirst()
        }

        tr.tick()
        XCTAssertNil(triggerStore.triggers.first?.lastFired)
        XCTAssertEqual(history.records(deviceId: "serial-a").count, 0)

        tr.tick()
        XCTAssertNotNil(triggerStore.triggers.first?.lastFired)
        XCTAssertEqual(history.records(deviceId: "serial-a").count, 1)
        XCTAssertEqual(history.records(deviceId: "serial-a")[0].log, ["skipped (preset missing)"])
        let firedAt = triggerStore.triggers.first?.lastFired

        tr.tick()
        tr.tick()
        XCTAssertEqual(triggerStore.triggers.first?.lastFired, firedAt)
        XCTAssertEqual(history.records(deviceId: "serial-a").count, 1)
    }

    func testOfflineDeviceDoesNotSeedOrFire() throws {
        let dir = try tempDir()
        let (triggerStore, _, _, devices, history, tr) = makeHarness(dir: dir)
        // No devices connected.
        addMissingTargetTrigger(
            store: triggerStore,
            deviceId: "gone",
            condition: .notificationMatch(packageContains: nil, textContains: nil)
        )
        tr.notificationFetcher = { _ in
            [PhoneNotification(package: "com.x", title: "t", text: "b", whenMs: 1)]
        }
        tr.tick()
        tr.tick()
        XCTAssertNil(triggerStore.triggers.first?.lastFired)
        XCTAssertEqual(history.records(deviceId: "gone").count, 0)
        _ = devices
    }

    func testForegroundEdgeFiresOncePerEnter() throws {
        let dir = try tempDir()
        let (triggerStore, _, _, devices, history, tr) = makeHarness(dir: dir)
        devices.devices = [
            Device(id: "s1", platform: .android, model: "P", osVersion: "14", status: "device")
        ]
        addMissingTargetTrigger(
            store: triggerStore,
            deviceId: "s1",
            condition: .appForeground(packageContains: "instagram")
        )

        var pkgs: [String?] = [
            "com.android.launcher3",   // seed
            "com.instagram.android",   // enter → fire
            "com.instagram.android",   // stay
            "com.android.chrome",      // leave
            "com.instagram.android",   // re-enter → fire
        ]
        tr.foregroundFetcher = { _ in
            guard !pkgs.isEmpty else { return "com.instagram.android" }
            return pkgs.removeFirst()
        }

        tr.tick()
        XCTAssertNil(triggerStore.triggers.first?.lastFired)
        XCTAssertEqual(history.records(deviceId: "s1").count, 0)

        tr.tick()
        let firstFire = triggerStore.triggers.first?.lastFired
        XCTAssertNotNil(firstFire)
        XCTAssertEqual(history.records(deviceId: "s1").count, 1)

        tr.tick()
        XCTAssertEqual(triggerStore.triggers.first?.lastFired, firstFire)
        XCTAssertEqual(history.records(deviceId: "s1").count, 1)

        tr.tick()
        XCTAssertEqual(history.records(deviceId: "s1").count, 1)

        tr.tick()
        XCTAssertNotEqual(triggerStore.triggers.first?.lastFired, firstFire)
        XCTAssertEqual(history.records(deviceId: "s1").count, 2)
    }

    func testSameNotificationDoesNotReFireAfterSkip() throws {
        let dir = try tempDir()
        let (triggerStore, _, _, devices, history, tr) = makeHarness(dir: dir)
        devices.devices = [
            Device(id: "s1", platform: .android, model: "P", osVersion: "14", status: "device")
        ]
        addMissingTargetTrigger(
            store: triggerStore,
            deviceId: "s1",
            condition: .notificationMatch(packageContains: "x", textContains: nil)
        )

        let seed = PhoneNotification(package: "com.other", title: "z", text: "b", whenMs: 1)
        let match = PhoneNotification(package: "com.x", title: "T", text: "b", whenMs: 9)
        var dumps: [[PhoneNotification]] = [
            [seed],
            [seed, match],
            [seed, match],
            [seed, match],
        ]
        tr.notificationFetcher = { _ in
            guard !dumps.isEmpty else { return [seed, match] }
            return dumps.removeFirst()
        }

        tr.tick() // seed
        tr.tick() // fire once → skip missing
        XCTAssertEqual(history.records(deviceId: "s1").count, 1)
        XCTAssertEqual(history.records(deviceId: "s1")[0].log, ["skipped (preset missing)"])

        tr.tick()
        tr.tick()
        XCTAssertEqual(history.records(deviceId: "s1").count, 1, "must not re-fire same notif")
    }

    func testDisabledTriggerIgnored() throws {
        let dir = try tempDir()
        let (triggerStore, _, _, devices, history, tr) = makeHarness(dir: dir)
        devices.devices = [
            Device(id: "s1", platform: .android, model: "P", osVersion: "14", status: "device")
        ]
        triggerStore.add(Trigger(
            name: "Off",
            enabled: false,
            deviceId: "s1",
            deviceName: "P",
            targetKind: .preset,
            targetId: UUID(),
            condition: .appForeground(packageContains: "x")
        ))
        var step = 0
        tr.foregroundFetcher = { _ in
            step += 1
            return step == 1 ? "com.other" : "com.x.app"
        }
        tr.tick()
        tr.tick()
        XCTAssertNil(triggerStore.triggers.first?.lastFired)
        XCTAssertEqual(history.records(deviceId: "s1").count, 0)
    }
}
