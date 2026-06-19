import AppKit
import ApplicationServices

enum WindowDockError: LocalizedError {
    case accessibilityNotTrusted
    case appNotFound(String)
    case windowNotFound(String)
    case setFrameFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            return "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility"
        case .appNotFound(let ownerName):
            return "\(ownerName) is not running"
        case .windowNotFound(let ownerName):
            return "No \(ownerName) window found"
        case .setFrameFailed:
            return "Could not move mirror window"
        }
    }
}

func isAccessibilityTrusted() -> Bool {
    AXIsProcessTrusted()
}

@discardableResult
func requestAccessibilityIfNeeded() -> Bool {
    guard !isAccessibilityTrusted() else { return true }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func findIPhoneMirroringApp() -> NSRunningApplication? {
    let running = NSWorkspace.shared.runningApplications
    return running.first { $0.bundleIdentifier == "com.apple.ScreenContinuity" }
        ?? running.first { $0.localizedName == "iPhone Mirroring" }
}

func dockWindow(ownerName: String, into rect: CGRect) throws {
    guard isAccessibilityTrusted() else { throw WindowDockError.accessibilityNotTrusted }

    let app = findRunningApplication(ownerName: ownerName)
    guard let app else { throw WindowDockError.appNotFound(ownerName) }
    app.activate()

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 0.4)

    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement],
          let window = windows.first else {
        throw WindowDockError.windowNotFound(ownerName)
    }

    AXUIElementSetMessagingTimeout(window, 0.4)
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
    AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)

    var position = rect.origin
    var size = rect.size
    guard let positionValue = AXValueCreate(.cgPoint, &position),
          let sizeValue = AXValueCreate(.cgSize, &size) else {
        throw WindowDockError.setFrameFailed
    }

    // AX requires position to be set before size; repeat to ensure both take effect.
    let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

    guard sizeResult == .success, positionResult == .success else {
        throw WindowDockError.setFrameFailed
    }
}

private func findRunningApplication(ownerName: String) -> NSRunningApplication? {
    let running = NSWorkspace.shared.runningApplications
    return running.first { $0.bundleIdentifier == ownerName }
        ?? running.first { $0.localizedName == ownerName }
        ?? running.first { $0.localizedName?.localizedCaseInsensitiveCompare(ownerName) == .orderedSame }
}
