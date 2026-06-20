import AppKit
import Foundation
import PhoneHubCore

@MainActor
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

    func dock(into rect: CGRect) async throws {
        activate()

        let deadline = Date().addingTimeInterval(6)
        var lastError: Error?

        while Date() < deadline {
            do {
                guard let app = findIPhoneMirroringApp() else {
                    throw WindowDockError.appNotFound(bundleID)
                }
                try await fitMirrorToRect(pid: app.processIdentifier, rect: rect)
                return
            } catch let error as WindowDockError {
                switch error {
                case .appNotFound, .windowNotFound:
                    lastError = error
                    try await Task.sleep(nanoseconds: 300_000_000)
                default:
                    throw error
                }
            } catch {
                throw error
            }
        }

        do {
            guard let app = findIPhoneMirroringApp() else {
                throw WindowDockError.appNotFound(bundleID)
            }
            try await fitMirrorToRect(pid: app.processIdentifier, rect: rect)
        } catch {
            throw lastError ?? error
        }
    }

    func stop() {
        findIPhoneMirroringApp()?.terminate()
    }
}
