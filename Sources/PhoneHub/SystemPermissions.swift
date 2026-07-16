import AppKit
import CoreGraphics
import IOKit.hidsystem

@MainActor
enum SystemPermissions {
    static var accessibilityGranted: Bool {
        isAccessibilityTrusted()
    }

    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestAccessibility() {
        _ = requestAccessibilityIfNeeded()
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        openSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    static func openScreenRecordingSettings() {
        openSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    static func openInputMonitoringSettings() {
        openSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    private static func openSettings(_ deepLink: String) {
        guard let url = URL(string: deepLink) else { return }
        NSWorkspace.shared.open(url)
    }
}
