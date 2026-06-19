import AppKit
import Foundation
import PhoneHubCore

final class MirroringController {
    private let bundleID = "com.apple.ScreenContinuity"

    func activate() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if error != nil {
                    _ = try? runTool("open", ["-b", self.bundleID], timeout: 5)
                }
            }
        } else {
            _ = try? runTool("open", ["-b", bundleID], timeout: 5)
        }
    }

    func dock(into rect: CGRect) throws {
        activate()

        let deadline = Date().addingTimeInterval(3)
        while findIPhoneMirroringApp() == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        try dockWindow(ownerName: bundleID, into: rect)
    }

    func stop() {
        findIPhoneMirroringApp()?.terminate()
    }
}
