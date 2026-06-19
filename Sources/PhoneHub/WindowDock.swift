import AppKit
import ApplicationServices
import PhoneHubCore

enum WindowDockError: LocalizedError {
    case accessibilityNotTrusted
    case appNotFound(String)
    case windowNotFound(String)
    case windowSizeUnavailable(String)
    case setFrameFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            return "Enable Accessibility for PhoneHub in System Settings -> Privacy -> Accessibility"
        case .appNotFound(let ownerName):
            return "\(ownerName) is not running"
        case .windowNotFound(let ownerName):
            return "No \(ownerName) window found"
        case .windowSizeUnavailable(let ownerName):
            return "Could not read \(ownerName) window size"
        case .setFrameFailed:
            return "Could not move mirror window"
        }
    }
}

@MainActor
func isAccessibilityTrusted() -> Bool {
    AXIsProcessTrusted()
}

@MainActor
@discardableResult
func requestAccessibilityIfNeeded() -> Bool {
    guard !isAccessibilityTrusted() else { return true }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

@MainActor
func findIPhoneMirroringApp() -> NSRunningApplication? {
    let running = NSWorkspace.shared.runningApplications
    return running.first { $0.bundleIdentifier == "com.apple.ScreenContinuity" }
        ?? running.first { $0.localizedName == "iPhone Mirroring" }
}

@MainActor
@discardableResult
func dockWindow(ownerName: String, into rect: CGRect) throws -> CGSize {
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

    guard let mirrorSize = readAXSize(window) else {
        throw WindowDockError.windowSizeUnavailable(ownerName)
    }

    let centeredRect = centeredRect(forContentSize: mirrorSize, within: rect, inset: 12)
    guard setAXPosition(window, to: centeredRect.origin) else {
        throw WindowDockError.setFrameFailed
    }

    return mirrorSize
}

@MainActor
@discardableResult
func dockWindow(byTitle titleSubstring: String, into rect: CGRect) throws -> CGSize {
    guard isAccessibilityTrusted() else { throw WindowDockError.accessibilityNotTrusted }

    guard let window = findWindow(titleContaining: titleSubstring) else {
        throw WindowDockError.windowNotFound(titleSubstring)
    }

    AXUIElementSetMessagingTimeout(window, 0.4)
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
    AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)

    let size = CGSize(width: max(0, rect.width), height: max(0, rect.height))
    guard setAXSize(window, to: size),
          setAXPosition(window, to: rect.origin) else {
        throw WindowDockError.setFrameFailed
    }

    return size
}

private func readAXSize(_ window: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }

    let axValue = value as! AXValue
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size),
          size.width > 0,
          size.height > 0 else {
        return nil
    }
    return size
}

private func readAXTitle(_ window: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
        return nil
    }
    return value as? String
}

private func setAXSize(_ window: AXUIElement, to size: CGSize) -> Bool {
    var size = size
    guard let sizeValue = AXValueCreate(.cgSize, &size) else {
        return false
    }

    return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
}

private func setAXPosition(_ window: AXUIElement, to point: CGPoint) -> Bool {
    var position = point
    guard let positionValue = AXValueCreate(.cgPoint, &position) else {
        return false
    }

    return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success
}

@MainActor
private func findWindow(titleContaining titleSubstring: String) -> AXUIElement? {
    for app in NSWorkspace.shared.runningApplications {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.2)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            continue
        }

        if let window = windows.first(where: { window in
            readAXTitle(window)?.localizedCaseInsensitiveContains(titleSubstring) == true
        }) {
            app.activate()
            return window
        }
    }

    return nil
}

@MainActor
private func findRunningApplication(ownerName: String) -> NSRunningApplication? {
    let running = NSWorkspace.shared.runningApplications
    return running.first { $0.bundleIdentifier == ownerName }
        ?? running.first { $0.localizedName == ownerName }
        ?? running.first { $0.localizedName?.localizedCaseInsensitiveCompare(ownerName) == .orderedSame }
}
