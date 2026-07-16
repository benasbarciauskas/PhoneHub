import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class DeviceStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    func testRemoveFiltersDeviceAndMovesFocus() {
        let removed = Device(id: "stale-ios", platform: .ios, model: "Old iPhone",
                             osVersion: "18.0", status: "notConnected")
        let remaining = Device(id: "android", platform: .android, model: "Pixel",
                               osVersion: "16", status: "device")
        let store = DeviceStore()
        store.devices = [removed, remaining]
        store.focusedDevice = removed

        store.remove(deviceId: removed.id)

        XCTAssertEqual(store.devices, [remaining])
        XCTAssertEqual(store.focusedDevice, remaining)
    }

    func testDiscoveryKeepsRemovedNotConnectedDeviceHidden() {
        let stale = Device(id: "stale-ios", platform: .ios, model: "Old iPhone",
                           osVersion: "18.0", status: "notConnected")
        let store = DeviceStore()
        store.mirrorPresenceProvider = { false }
        store.devices = [stale]

        store.remove(deviceId: stale.id)
        store.applyDiscovery([stale])

        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(store.focusedDevice)
    }

    func testDiscoveryRestoresRemovedDeviceOnRealPresence() {
        let stale = Device(id: "ios", platform: .ios, model: "iPhone",
                           osVersion: "18.0", status: "notConnected")
        let connected = Device(id: stale.id, platform: .ios, model: stale.model,
                               osVersion: stale.osVersion, status: "connected")
        let store = DeviceStore()
        store.devices = [stale]

        store.remove(deviceId: stale.id)
        store.applyDiscovery([connected])

        XCTAssertEqual(store.devices, [connected])
        XCTAssertEqual(store.focusedDevice, connected)
    }

    func testSetNamePersistsAndRoundTrips() throws {
        let directory = try temporaryDirectory()
        let device = Device(id: "ios", platform: .ios, model: "iPhone 16 Pro",
                            osVersion: "18.0", status: "connected")
        let store = DeviceStore(directory: directory)

        store.setName(deviceId: device.id, name: "Work Phone")

        let reopened = DeviceStore(directory: directory)
        XCTAssertEqual(reopened.displayName(for: device), "Work Phone")
    }

    func testDisplayNameFallsBackToDiscoveredModelWhenUnset() throws {
        let store = DeviceStore(directory: try temporaryDirectory())
        let device = Device(id: "android", platform: .android, model: "Pixel 10",
                            osVersion: "16", status: "device")

        XCTAssertEqual(store.displayName(for: device), "Pixel 10")
    }

    func testEmptyNameClearsCustomName() throws {
        let store = DeviceStore(directory: try temporaryDirectory())
        let device = Device(id: "ios", platform: .ios, model: "iPhone 16 Pro",
                            osVersion: "18.0", status: "connected")
        store.setName(deviceId: device.id, name: "Work Phone")

        store.setName(deviceId: device.id, name: "   ")

        XCTAssertEqual(store.displayName(for: device), "iPhone 16 Pro")
    }

    func testDiscoveryKeepsCustomNameWithoutMutatingModel() throws {
        let store = DeviceStore(directory: try temporaryDirectory())
        let original = Device(id: "ios", platform: .ios, model: "iPhone 15",
                              osVersion: "17.0", status: "notConnected")
        store.setName(deviceId: original.id, name: "Personal Phone")

        let rediscovered = Device(id: original.id, platform: .ios, model: "iPhone 16 Pro",
                                  osVersion: "18.0", status: "connected")
        store.applyDiscovery([rediscovered])

        XCTAssertEqual(store.devices.first?.model, "iPhone 16 Pro")
        XCTAssertEqual(store.displayName(for: store.devices[0]), "Personal Phone")
    }

    func testWallLayoutStateIsKeptInMemoryAcrossDiscovery() throws {
        let store = DeviceStore(directory: try temporaryDirectory())
        store.wallGridPreset = .threeByTwo
        store.wallTileOrder = ["pixel": 1, "iphone": 0]
        store.wallZoomByDeviceID = ["pixel": 0.6]

        store.applyDiscovery([
            Device(id: "pixel", platform: .android, model: "Pixel",
                   osVersion: "16", status: "device"),
            Device(id: "iphone", platform: .ios, model: "iPhone",
                   osVersion: "18", status: "connected"),
        ])

        XCTAssertEqual(store.wallGridPreset, .threeByTwo)
        XCTAssertEqual(store.wallTileOrder, ["pixel": 1, "iphone": 0])
        XCTAssertEqual(store.wallZoomByDeviceID, ["pixel": 0.6])
    }

    func testWallLayoutStateIsNotPersisted() throws {
        let directory = try temporaryDirectory()
        let store = DeviceStore(directory: directory)
        store.wallGridPreset = .row
        store.wallTileOrder = ["pixel": 3]
        store.wallZoomByDeviceID = ["pixel": 0.5]

        let reopened = DeviceStore(directory: directory)

        XCTAssertEqual(reopened.wallGridPreset, .auto)
        XCTAssertTrue(reopened.wallTileOrder.isEmpty)
        XCTAssertTrue(reopened.wallZoomByDeviceID.isEmpty)
    }
}

@MainActor
final class DeviceStoreMirrorPresenceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceStoreMirror-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRemovedIPhoneReturnsWhenMirroringIsActive() throws {
        let store = DeviceStore(directory: try temporaryDirectory())
        let iphone = Device(id: "udid-16pro", platform: .ios, model: "iPhone 16 Pro",
                            osVersion: "26.3", status: "notConnected")
        store.mirrorPresenceProvider = { false }
        store.applyDiscovery([iphone])
        store.remove(deviceId: iphone.id)

        // Still hidden while no mirror window exists.
        store.applyDiscovery([iphone])
        XCTAssertTrue(store.devices.isEmpty)

        // User reconnects via iPhone Mirroring: device reappears with its name.
        store.mirrorPresenceProvider = { true }
        store.applyDiscovery([iphone])
        XCTAssertEqual(store.devices.map(\.model), ["iPhone 16 Pro"])
    }

    func testRemovedIPhoneStillReturnsOnUSBConnection() throws {
        let store = DeviceStore(directory: try temporaryDirectory())
        store.mirrorPresenceProvider = { false }
        let iphone = Device(id: "udid-1", platform: .ios, model: "iPhone 13 Pro",
                            osVersion: "26.6", status: "connected")
        store.applyDiscovery([iphone])
        store.remove(deviceId: iphone.id)

        store.applyDiscovery([iphone])
        XCTAssertEqual(store.devices.count, 1)
    }
}
