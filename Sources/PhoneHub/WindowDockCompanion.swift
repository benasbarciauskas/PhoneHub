import AppKit
import ApplicationServices
import PhoneHubCore

/// Companion layout: leave the mirror at native size; reposition (and raise)
/// only so it sits beside PhoneHub. Never opens View menus or writes AX size.
@MainActor
@discardableResult
func dockWindowBeside(ownerName: String,
                      phoneHubFrame: CGRect,
                      gap: CGFloat = StageLayout.companionGap,
                      activate: Bool = true) throws -> CGSize {
    guard isAccessibilityTrusted() else { throw WindowDockError.accessibilityNotTrusted }

    let app = findRunningApplication(ownerName: ownerName)
    guard let app else { throw WindowDockError.appNotFound(ownerName) }
    if activate {
        app.activate()
    }

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 0.4)

    guard let window = firstWindow(in: appElement) else {
        throw WindowDockError.windowNotFound(ownerName)
    }

    AXUIElementSetMessagingTimeout(window, 0.4)
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
    AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)

    guard let mirrorSize = readAXSize(window) else {
        throw WindowDockError.windowSizeUnavailable(ownerName)
    }

    let origin = companionMirrorOrigin(phoneHubFrame: phoneHubFrame,
                                       mirrorSize: mirrorSize,
                                       gap: gap,
                                       visibleFrame: axVisibleFrame(containing: phoneHubFrame))
    guard repositionAXWindowIfNeeded(window, to: origin) else {
        throw WindowDockError.setFrameFailed
    }

    trackDockedIPhoneMirroringWindow(processIdentifier: app.processIdentifier)
    return mirrorSize
}

/// Companion layout for a titled scrcpy window: reposition only, keep launched size.
@MainActor
@discardableResult
func dockWindowBeside(byTitle title: String,
                      processIdentifier: pid_t,
                      phoneHubFrame: CGRect,
                      gap: CGFloat = StageLayout.companionGap) throws -> CGSize {
    guard isAccessibilityTrusted() else { throw WindowDockError.accessibilityNotTrusted }

    guard let window = findWindow(title: title, processIdentifier: processIdentifier) else {
        throw WindowDockError.windowNotFound(title)
    }

    AXUIElementSetMessagingTimeout(window, 0.4)
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
    AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)

    guard let mirrorSize = readAXSize(window) else {
        throw WindowDockError.windowSizeUnavailable(title)
    }

    let origin = companionMirrorOrigin(phoneHubFrame: phoneHubFrame,
                                       mirrorSize: mirrorSize,
                                       gap: gap,
                                       visibleFrame: axVisibleFrame(containing: phoneHubFrame))
    guard repositionAXWindowIfNeeded(window, to: origin) else {
        throw WindowDockError.setFrameFailed
    }

    return mirrorSize
}

/// Visible frame of the screen containing `rect` (AX top-left coordinates).
@MainActor
func axVisibleFrame(containing rect: CGRect) -> CGRect {
    guard let primary = NSScreen.screens.first else {
        return CGRect(x: rect.minX - 10_000, y: rect.minY - 10_000,
                      width: 20_000, height: 20_000)
    }
    let primaryHeight = primary.frame.height
    let cocoaPoint = NSPoint(x: rect.midX, y: primaryHeight - rect.midY)
    let screen = NSScreen.screens.first { NSMouseInRect(cocoaPoint, $0.frame, false) }
        ?? NSScreen.main
        ?? primary
    let visible = screen.visibleFrame
    return CGRect(x: visible.minX,
                  y: primaryHeight - visible.maxY,
                  width: visible.width,
                  height: visible.height)
}
