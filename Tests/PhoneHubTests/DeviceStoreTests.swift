import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class DeviceStoreTests: XCTestCase {
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
}
