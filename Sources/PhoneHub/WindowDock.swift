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
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity").first
        ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == "iPhone Mirroring" }
}

@MainActor
@discardableResult
func dockWindow(ownerName: String, into rect: CGRect, activate: Bool = true) throws -> CGSize {
    guard isAccessibilityTrusted() else { throw WindowDockError.accessibilityNotTrusted }

    let app = findRunningApplication(ownerName: ownerName)
    guard let app else { throw WindowDockError.appNotFound(ownerName) }
    if activate {
        app.activate()
    }

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

    guard let mirrorSize = readAXSize(window) else {
        throw WindowDockError.windowSizeUnavailable(ownerName)
    }

    let centeredRect = centeredRect(forContentSize: mirrorSize, within: rect, inset: 12)
    guard repositionAXWindowIfNeeded(window, to: centeredRect.origin) else {
        throw WindowDockError.setFrameFailed
    }

    return mirrorSize
}

@MainActor
@discardableResult
func dockWindow(byTitle title: String, processIdentifier: pid_t, into rect: CGRect) throws -> CGSize {
    guard isAccessibilityTrusted() else { throw WindowDockError.accessibilityNotTrusted }

    guard let window = findWindow(title: title, processIdentifier: processIdentifier) else {
        throw WindowDockError.windowNotFound(title)
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

@MainActor
func pressViewMenuItem(pid: Int32, named name: String) -> Bool {
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 0.4)

    guard let menuBarValue = copyAXAttribute(appElement, kAXMenuBarAttribute as CFString),
          CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else {
        return false
    }

    let menuBar = menuBarValue as! AXUIElement
    guard let menuBarItems = copyAXAttribute(menuBar, kAXChildrenAttribute as CFString) as? [AXUIElement],
          let viewMenuBarItem = menuBarItems.first(where: { readAXTitle($0) == "View" }) else {
        return false
    }

    AXUIElementSetMessagingTimeout(viewMenuBarItem, 0.4)
    _ = AXUIElementPerformAction(viewMenuBarItem, kAXPressAction as CFString)

    guard let viewMenu = firstAXMenu(from: viewMenuBarItem),
          let menuItems = copyAXAttribute(viewMenu, kAXChildrenAttribute as CFString) as? [AXUIElement],
          let item = menuItems.first(where: { readAXTitle($0) == name }) else {
        return false
    }

    AXUIElementSetMessagingTimeout(item, 0.4)
    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
}

@MainActor
@discardableResult
func fitMirrorToRect(pid: Int32, rect: CGRect) async throws -> CGSize {
    guard isAccessibilityTrusted() else { throw WindowDockError.accessibilityNotTrusted }

    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 0.4)

    guard let window = firstWindow(in: appElement) else {
        throw WindowDockError.windowNotFound("com.apple.ScreenContinuity")
    }

    AXUIElementSetMessagingTimeout(window, 0.4)
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
    AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)

    guard var currentSize = readAXSize(window) else {
        throw WindowDockError.windowSizeUnavailable("com.apple.ScreenContinuity")
    }

    let inset: CGFloat = 12
    let insetX = min(inset, max(0, rect.width / 2))
    let insetY = min(inset, max(0, rect.height / 2))
    let targetSize = rect.insetBy(dx: insetX, dy: insetY).size
    NSLog("PhoneHub fitting iPhone Mirroring into stage rect %@ (content target %@)",
          NSStringFromRect(rect), NSStringFromSize(targetSize))

    let maxIterations = 64
    var iterationCount = 0
    var seenSizes: Set<String> = [roundedSizeKey(currentSize)]
    var observedSizes: [CGSize] = [currentSize]

    func pressAndRead(_ actionName: String) async throws -> CGSize? {
        guard pressViewMenuItem(pid: pid, named: actionName) else {
            return nil
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        return readAXSize(window)
    }

    func recordSeenSize(_ size: CGSize) -> Bool {
        let inserted = seenSizes.insert(roundedSizeKey(size)).inserted
        if inserted {
            observedSizes.append(size)
        }
        return inserted
    }

    while exceedsTarget(currentSize, target: targetSize), iterationCount < maxIterations {
        iterationCount += 1

        guard let nextSize = try await pressAndRead("Smaller") else {
            break
        }

        if sizesAreEffectivelyEqual(currentSize, nextSize) {
            currentSize = nextSize
            break
        }

        currentSize = nextSize
        guard recordSeenSize(currentSize) else {
            if exceedsTarget(currentSize, target: targetSize),
               let smallerSize = try await pressAndRead("Smaller") {
                currentSize = smallerSize
                _ = recordSeenSize(smallerSize)
            }
            break
        }
    }

    while !exceedsTarget(currentSize, target: targetSize), iterationCount < maxIterations {
        if fitStep(current: currentSize, target: targetSize) == .smaller {
            break
        }

        iterationCount += 1
        let lastFittingSize = currentSize
        guard let nextSize = try await pressAndRead("Larger") else {
            break
        }

        if sizesAreEffectivelyEqual(currentSize, nextSize) {
            currentSize = nextSize
            break
        }

        currentSize = nextSize
        let wasNewSize = recordSeenSize(currentSize)

        if exceedsTarget(currentSize, target: targetSize) {
            if let smallerSize = try await pressAndRead("Smaller"),
               !exceedsTarget(smallerSize, target: targetSize) {
                currentSize = smallerSize
            } else {
                currentSize = lastFittingSize
            }
            break
        }

        guard wasNewSize else {
            break
        }
    }

    guard let selectedMenuSize = selectFinalMirrorMenuSize(from: observedSizes, target: targetSize) else {
        throw WindowDockError.windowSizeUnavailable("com.apple.ScreenContinuity")
    }
    let constrainedSize = aspectFitSize(selectedMenuSize, within: targetSize)
    guard constrainedSize.width > 0, constrainedSize.height > 0 else {
        throw WindowDockError.setFrameFailed
    }

    if !sizesAreEffectivelyEqual(currentSize, constrainedSize) {
        guard setAXSize(window, to: constrainedSize) else {
            throw WindowDockError.setFrameFailed
        }
    }

    guard var finalSize = readAXSize(window) else {
        throw WindowDockError.windowSizeUnavailable("com.apple.ScreenContinuity")
    }
    if exceedsTarget(finalSize, target: targetSize) {
        let retrySize = aspectFitSize(finalSize, within: targetSize)
        guard retrySize.width > 0,
              retrySize.height > 0,
              setAXSize(window, to: retrySize),
              let verifiedSize = readAXSize(window),
              !exceedsTarget(verifiedSize, target: targetSize) else {
            throw WindowDockError.setFrameFailed
        }
        finalSize = verifiedSize
    }

    return try centerAXWindow(window, size: finalSize, in: rect)
}

private func exceedsTarget(_ size: CGSize, target: CGSize) -> Bool {
    size.width > target.width || size.height > target.height
}

private func roundedSizeKey(_ size: CGSize) -> String {
    "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
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

private func readAXPosition(_ window: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }

    let axValue = value as! AXValue
    var position = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &position) else {
        return nil
    }
    return position
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

/// Keep raise on the same deduplicated path as the AX position write. Raising
/// after the write restores z-order without activating PhoneHub or opening menus.
private func repositionAXWindowIfNeeded(_ window: AXUIElement, to point: CGPoint) -> Bool {
    guard shouldRepositionWindow(current: readAXPosition(window), target: point, tolerance: 1) else {
        return true
    }
    guard setAXPosition(window, to: point) else { return false }
    _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    return true
}

private func copyAXAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return value
}

private func firstAXMenu(from menuBarItem: AXUIElement) -> AXUIElement? {
    if let menuValue = copyAXAttribute(menuBarItem, "AXMenu" as CFString),
       CFGetTypeID(menuValue) == AXUIElementGetTypeID() {
        return (menuValue as! AXUIElement)
    }

    guard let children = copyAXAttribute(menuBarItem, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
        return nil
    }
    return children.first { child in
        copyAXAttribute(child, kAXRoleAttribute as CFString) as? String == (kAXMenuRole as String)
    }
}

private func firstWindow(in appElement: AXUIElement) -> AXUIElement? {
    guard let windows = copyAXAttribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
        return nil
    }
    return windows.first
}

private func centerAXWindow(_ window: AXUIElement, size: CGSize, in rect: CGRect) throws -> CGSize {
    let centeredRect = centeredRect(forContentSize: size, within: rect, inset: 12)
    guard repositionAXWindowIfNeeded(window, to: centeredRect.origin) else {
        throw WindowDockError.setFrameFailed
    }
    return size
}

private func sizesAreEffectivelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
    abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
}

@MainActor
private func findWindow(title: String, processIdentifier: pid_t) -> AXUIElement? {
    let appElement = AXUIElementCreateApplication(processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 0.2)

    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else {
        return nil
    }

    return windows.first { window in
        readAXTitle(window) == title
    }
}

@MainActor
private func findRunningApplication(ownerName: String) -> NSRunningApplication? {
    let running = NSWorkspace.shared.runningApplications
    return running.first { $0.bundleIdentifier == ownerName }
        ?? running.first { $0.localizedName == ownerName }
        ?? running.first { $0.localizedName?.localizedCaseInsensitiveCompare(ownerName) == .orderedSame }
}
