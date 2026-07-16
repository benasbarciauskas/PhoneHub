import AppKit
import ApplicationServices
import Foundation

// MARK: - Pure matcher (unit-tested)

/// Index pair into a list of popup-menu title arrays.
struct IPhonePopupMatch: Equatable, Sendable {
    let popupIndex: Int
    let itemIndex: Int
}

/// Given title arrays for each AX pop-up button's menu items and one or more
/// target device names, return which popup + item matches — or nil.
///
/// Matching order: exact equality → case-insensitive equality → bidirectional
/// case-insensitive containment. Never invents a match when nothing looks right.
func matchIPhonePopupMenuItem(
    targetNames: [String],
    popupMenus: [[String]]
) -> IPhonePopupMatch? {
    let targets = targetNames
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !targets.isEmpty else { return nil }

    for (popupIndex, items) in popupMenus.enumerated() {
        for (itemIndex, item) in items.enumerated() {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            for target in targets where trimmed == target {
                return IPhonePopupMatch(popupIndex: popupIndex, itemIndex: itemIndex)
            }
        }
    }

    for (popupIndex, items) in popupMenus.enumerated() {
        for (itemIndex, item) in items.enumerated() {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            for target in targets where trimmed.caseInsensitiveCompare(target) == .orderedSame {
                return IPhonePopupMatch(popupIndex: popupIndex, itemIndex: itemIndex)
            }
        }
    }

    for (popupIndex, items) in popupMenus.enumerated() {
        for (itemIndex, item) in items.enumerated() {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            for target in targets {
                if trimmed.localizedCaseInsensitiveContains(target)
                    || target.localizedCaseInsensitiveContains(trimmed) {
                    return IPhonePopupMatch(popupIndex: popupIndex, itemIndex: itemIndex)
                }
            }
        }
    }

    return nil
}

// MARK: - Switch result

/// Shared copy for UI + unit tests (not MainActor-bound).
let iPhonePickerUnavailableMessage =
    "Can't switch — macOS only offers the iPhone picker when 2+ iPhones (same Apple Account, nearby) are available. Connect the other iPhone and try again."

enum IPhoneSwitchResult: Equatable, Sendable {
    case switched
    case pickerUnavailable
    case accessibilityRequired
    case timedOut
    case failed(String)

    /// Message for Sidebar alert; nil on success.
    var userMessage: String? {
        switch self {
        case .switched:
            return nil
        case .pickerUnavailable:
            return iPhonePickerUnavailableMessage
        case .accessibilityRequired:
            return "Enable Accessibility for PhoneHub in System Settings → Privacy & Security → Accessibility"
        case .timedOut:
            return "Timed out waiting for System Settings. Try again."
        case .failed(let message):
            return message
        }
    }
}

// MARK: - System Settings driver

/// Best-effort switch of the OS-paired iPhone via System Settings → Desktop & Dock.
/// Drives another app's UI; every AX call is guarded and the whole probe is time-boxed.
@MainActor
enum IPhoneSwitcher {
    static var pickerUnavailableMessage: String { iPhonePickerUnavailableMessage }

    private static let settingsBundleID = "com.apple.systempreferences"
    private static let desktopSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
    private static let searchBudgetSeconds: TimeInterval = 3.0

    /// Switch iPhone Mirroring's paired device to one whose menu title matches any of `deviceNames`.
    static func switchMirroring(toDeviceNames deviceNames: [String]) async -> IPhoneSwitchResult {
        let names = deviceNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else {
            return .failed("No device name available to match in System Settings.")
        }

        guard isAccessibilityTrusted() else {
            requestAccessibilityIfNeeded()
            return .accessibilityRequired
        }

        guard NSWorkspace.shared.open(desktopSettingsURL) else {
            return .failed("Could not open System Settings → Desktop & Dock.")
        }

        guard let settingsApp = await waitForSystemSettings(timeout: searchBudgetSeconds) else {
            return .timedOut
        }

        let appElement = AXUIElementCreateApplication(settingsApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.4)

        let deadline = Date().addingTimeInterval(searchBudgetSeconds)
        while Date() < deadline {
            guard let window = firstSettingsWindow(in: appElement) else {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            let result = await probeAndSelect(
                in: window,
                targetNames: names,
                deadline: deadline
            )
            switch result {
            case .switched:
                closeSystemSettings(settingsApp)
                return .switched
            case .pickerUnavailable:
                // Keep probing until budget expires — pane may still be loading.
                try? await Task.sleep(nanoseconds: 150_000_000)
            case .accessibilityRequired, .timedOut, .failed:
                return result
            }
        }

        closeSystemSettings(settingsApp)
        return .pickerUnavailable
    }

    // MARK: Probe

    /// Walk pop-up buttons, open each menu at most once per attempt, select only a matched item.
    private static func probeAndSelect(
        in window: AXUIElement,
        targetNames: [String],
        deadline: Date
    ) async -> IPhoneSwitchResult {
        AXUIElementSetMessagingTimeout(window, 0.4)
        let popups = collectPopUpButtons(from: window, limit: 48)
        guard !popups.isEmpty else { return .pickerUnavailable }

        // Prefer controls that already look like the Desktop & Dock "iPhone" popup.
        let ordered = prioritizedPopUps(popups)

        var menuTitleArrays: [[String]] = []
        var livePopUps: [AXUIElement] = []
        var liveMenus: [AXUIElement] = []
        var liveItems: [[AXUIElement]] = []

        for popup in ordered {
            guard Date() < deadline else { break }

            guard let opened = openPopUpMenu(popup) else { continue }
            try? await Task.sleep(nanoseconds: 80_000_000)

            let items = menuItems(from: opened.menu)
            let titles = items.compactMap { readAXTitle($0) ?? readAXDescription($0) }
            // Dismiss immediately if this menu cannot match — never leave wrong menus open.
            if matchIPhonePopupMenuItem(targetNames: targetNames, popupMenus: [titles]) == nil {
                dismissMenu(popup: popup)
                continue
            }

            menuTitleArrays.append(titles)
            livePopUps.append(popup)
            liveMenus.append(opened.menu)
            liveItems.append(items)
            // We have a candidate popup open; stop opening more.
            break
        }

        guard let match = matchIPhonePopupMenuItem(
            targetNames: targetNames,
            popupMenus: menuTitleArrays
        ) else {
            for popup in livePopUps { dismissMenu(popup: popup) }
            return .pickerUnavailable
        }

        guard match.popupIndex < liveItems.count,
              match.itemIndex < liveItems[match.popupIndex].count else {
            for popup in livePopUps { dismissMenu(popup: popup) }
            return .pickerUnavailable
        }

        let item = liveItems[match.popupIndex][match.itemIndex]
        AXUIElementSetMessagingTimeout(item, 0.4)
        let pressed = AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        if !pressed {
            dismissMenu(popup: livePopUps[match.popupIndex])
            return .failed("Could not select the iPhone in System Settings.")
        }

        // Brief settle so Continuity / Mirroring can re-pair before caller re-docks.
        try? await Task.sleep(nanoseconds: 400_000_000)
        return .switched
    }

    // MARK: AX helpers

    private static func waitForSystemSettings(timeout: TimeInterval) async -> NSRunningApplication? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = findSystemSettingsApp() {
                let el = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(el, 0.3)
                if firstSettingsWindow(in: el) != nil {
                    return app
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return findSystemSettingsApp()
    }

    private static func findSystemSettingsApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).first
            ?? NSWorkspace.shared.runningApplications.first {
                $0.localizedName == "System Settings" || $0.localizedName == "System Preferences"
            }
    }

    private static func firstSettingsWindow(in appElement: AXUIElement) -> AXUIElement? {
        guard let windows = copyAXAttribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement],
              let window = windows.first else {
            return nil
        }
        return window
    }

    private static func collectPopUpButtons(from root: AXUIElement, limit: Int) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var queue: [AXUIElement] = [root]
        var visited = 0
        let maxVisit = 400

        while !queue.isEmpty, found.count < limit, visited < maxVisit {
            visited += 1
            let element = queue.removeFirst()
            let role = copyAXAttribute(element, kAXRoleAttribute as CFString) as? String
            if role == (kAXPopUpButtonRole as String) {
                found.append(element)
            }
            if let children = copyAXAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return found
    }

    /// Prefer a popup titled/described "iPhone"; still search by menu content only for selection.
    private static func prioritizedPopUps(_ popups: [AXUIElement]) -> [AXUIElement] {
        func looksLikeIPhoneControl(_ popup: AXUIElement) -> Bool {
            let title = (readAXTitle(popup) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = (readAXDescription(popup) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return title.caseInsensitiveCompare("iPhone") == .orderedSame
                || desc.caseInsensitiveCompare("iPhone") == .orderedSame
                || title.localizedCaseInsensitiveContains("iPhone")
                || desc.localizedCaseInsensitiveContains("iPhone")
        }
        let preferred = popups.filter(looksLikeIPhoneControl)
        if preferred.isEmpty { return popups }
        let rest = popups.filter { !looksLikeIPhoneControl($0) }
        return preferred + rest
    }

    private static func openPopUpMenu(_ popup: AXUIElement) -> (menu: AXUIElement, items: [AXUIElement])? {
        AXUIElementSetMessagingTimeout(popup, 0.4)
        // Already open?
        if let menu = firstAXMenu(from: popup) {
            let items = menuItems(from: menu)
            if !items.isEmpty { return (menu, items) }
        }

        guard AXUIElementPerformAction(popup, kAXPressAction as CFString) == .success else {
            return nil
        }

        if let menu = firstAXMenu(from: popup) {
            return (menu, menuItems(from: menu))
        }
        // Some hierarchy places the menu as a sibling under the window; scan children once.
        if let children = copyAXAttribute(popup, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            for child in children {
                let role = copyAXAttribute(child, kAXRoleAttribute as CFString) as? String
                if role == (kAXMenuRole as String) {
                    return (child, menuItems(from: child))
                }
            }
        }
        return nil
    }

    private static func menuItems(from menu: AXUIElement) -> [AXUIElement] {
        guard let children = copyAXAttribute(menu, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
            return []
        }
        return children.filter { child in
            let role = copyAXAttribute(child, kAXRoleAttribute as CFString) as? String
            return role == (kAXMenuItemRole as String)
        }
    }

    private static func dismissMenu(popup: AXUIElement) {
        // Second press usually collapses a pop-up; Escape as fallback.
        _ = AXUIElementPerformAction(popup, kAXCancelAction as CFString)
        postEscapeKey()
    }

    private static func postEscapeKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func readAXDescription(_ element: AXUIElement) -> String? {
        copyAXAttribute(element, kAXDescriptionAttribute as CFString) as? String
    }

    private static func closeSystemSettings(_ app: NSRunningApplication) {
        // Optional cleanup — fail soft; do not force-kill if terminate is refused.
        _ = app.terminate()
    }
}
