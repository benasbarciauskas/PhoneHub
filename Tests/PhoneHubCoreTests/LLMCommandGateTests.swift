import XCTest
@testable import PhoneHubCore

final class LLMCommandGateTests: XCTestCase {
    private let iPhone = Device(id: "udid-1", platform: .ios, model: "iPhone 16 Pro",
                                osVersion: "26.3", status: "notConnected")
    private let android = Device(id: "serial-1", platform: .android, model: "Pixel 8",
                                 osVersion: "15", status: "device")

    func testNoDeviceBlocks() {
        XCTAssertNotNil(llmCommandBlockReason(device: nil, iosMirrorWindowVisible: true))
    }

    func testIOSRequiresVisibleMirror() {
        XCTAssertNotNil(llmCommandBlockReason(device: iPhone, iosMirrorWindowVisible: false))
        XCTAssertNil(llmCommandBlockReason(device: iPhone, iosMirrorWindowVisible: true))
    }

    func testIOSBlockReasonNamesDevice() {
        let reason = llmCommandBlockReason(device: iPhone, iosMirrorWindowVisible: false)
        XCTAssertTrue(reason?.contains("iPhone 16 Pro") == true)
    }

    func testAndroidRequiresReadyStatus() {
        XCTAssertNil(llmCommandBlockReason(device: android, iosMirrorWindowVisible: false))
        let offline = Device(id: "serial-1", platform: .android, model: "Pixel 8",
                             osVersion: "15", status: "offline")
        XCTAssertNotNil(llmCommandBlockReason(device: offline, iosMirrorWindowVisible: true))
    }

    func testMirrorWindowDetection() {
        // Real captures: mirror = 418x920 untitled or "iPhone Mirroring";
        // pairing flow = 640x662 "Welcome to iPhone Mirroring"; menu-bar strips.
        let mirror = MirrorWindowCandidate(title: "iPhone Mirroring", layer: 0,
                                           width: 418, height: 920)
        let untitledMirror = MirrorWindowCandidate(title: "", layer: 0,
                                                   width: 418, height: 920)
        let welcome = MirrorWindowCandidate(title: "Welcome to iPhone Mirroring", layer: 0,
                                            width: 640, height: 662)
        let strip = MirrorWindowCandidate(title: "", layer: 0, width: 1710, height: 39)
        let overlay = MirrorWindowCandidate(title: "", layer: 25, width: 418, height: 920)

        XCTAssertTrue(containsLiveMirrorWindow([strip, welcome, mirror]))
        XCTAssertTrue(containsLiveMirrorWindow([untitledMirror]))
        XCTAssertFalse(containsLiveMirrorWindow([welcome]))
        XCTAssertFalse(containsLiveMirrorWindow([strip]))
        XCTAssertFalse(containsLiveMirrorWindow([overlay]))
        XCTAssertFalse(containsLiveMirrorWindow([]))
    }
}
