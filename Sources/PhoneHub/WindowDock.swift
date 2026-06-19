import AppKit
import ApplicationServices
import PhoneHubCore

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

    let currentSize = readAXSize(window) ?? CGSize(width: 9, height: 19.5)
    let initialAspect = aspectRatio(for: currentSize)
    let initialRect = aspectFitRect(aspectRatio: initialAspect, in: rect, inset: 8)

    guard setAXFrame(window, to: initialRect) else {
        throw WindowDockError.setFrameFailed
    }

    let actualSize = readAXSize(window) ?? initialRect.size
    let finalAspect = aspectRatio(for: actualSize)
    let finalRect = aspectFitRect(aspectRatio: finalAspect, in: rect, inset: 8)

    guard setAXFrame(window, to: finalRect) else {
        throw WindowDockError.setFrameFailed
    }
}

@MainActor
private func findRunningApplication(ownerName: String) -> NSRunningApplication? {
    let running = NSWorkspace.shared.runningApplications
    return running.first { $0.bundleIdentifier == ownerName }
        ?? running.first { $0.localizedName == ownerName }
        ?? running.first { $0.localizedName?.localizedCaseInsensitiveCompare(ownerName) == .orderedSame }
}

private func aspectRatio(for size: CGSize) -> CGFloat {
    guard size.width > 0, size.height > 0 else {
        return 9 / 19.5
    }
    return size.width / size.height
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

private func setAXFrame(_ window: AXUIElement, to rect: CGRect) -> Bool {
    var position = rect.origin
    var size = rect.size
    guard let positionValue = AXValueCreate(.cgPoint, &position),
          let sizeValue = AXValueCreate(.cgSize, &size) else {
        return false
    }

    // AX applies mirror window geometry most reliably when position brackets size.
    let firstPositionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    let finalPositionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

    return firstPositionResult == .success && sizeResult == .success && finalPositionResult == .success
}
