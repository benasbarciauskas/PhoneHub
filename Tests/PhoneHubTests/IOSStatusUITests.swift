import XCTest
@testable import PhoneHub
import PhoneHubCore

final class IOSStatusUITests: XCTestCase {
    func testSidebarIOSStatusColorsFollowConnectionStatus() {
        let connected = Device(id: "ios-connected",
                               platform: .ios,
                               model: "iPhone 13 Pro",
                               osVersion: "26.6",
                               status: "connected")
        let notConnected = Device(id: "ios-not-connected",
                                  platform: .ios,
                                  model: "iPhone 16 Pro",
                                  osVersion: "26.6",
                                  status: "notConnected")

        XCTAssertEqual(sidebarStatusColorRole(for: connected), .ok)
        XCTAssertEqual(sidebarStatusColorRole(for: notConnected), .warn)
    }

    func testSidebarAndroidStatusColorsAreUnchanged() {
        XCTAssertEqual(sidebarStatusColorRole(for: Device(id: "android-ready",
                                                          platform: .android,
                                                          model: "Pixel",
                                                          osVersion: "15",
                                                          status: "device")), .ok)
        XCTAssertEqual(sidebarStatusColorRole(for: Device(id: "android-auth",
                                                          platform: .android,
                                                          model: "Pixel",
                                                          osVersion: "15",
                                                          status: "unauthorized")), .warn)
        XCTAssertEqual(sidebarStatusColorRole(for: Device(id: "android-offline",
                                                          platform: .android,
                                                          model: "Pixel",
                                                          osVersion: "15",
                                                          status: "offline")), .err)
    }

    func testStagePlaceholderOnlyAppliesToNotConnectedIOSDevices() {
        let notConnected = Device(id: "ios-not-connected",
                                  platform: .ios,
                                  model: "iPhone 16 Pro",
                                  osVersion: "26.6",
                                  status: "notConnected")
        let connected = Device(id: "ios-connected",
                               platform: .ios,
                               model: "iPhone 13 Pro",
                               osVersion: "26.6",
                               status: "connected")
        let android = Device(id: "android",
                             platform: .android,
                             model: "Pixel",
                             osVersion: "15",
                             status: "offline")

        XCTAssertEqual(stageNotConnectedIOSPlaceholder(for: notConnected),
                       StagePlaceholder(title: "iPhone 16 Pro — not connected",
                                        detail: "Bring it near + unlock (same Apple ID), or it may be mirrored elsewhere. macOS mirrors one iPhone at a time."))
        XCTAssertNil(stageNotConnectedIOSPlaceholder(for: connected))
        XCTAssertNil(stageNotConnectedIOSPlaceholder(for: android))
    }
}
