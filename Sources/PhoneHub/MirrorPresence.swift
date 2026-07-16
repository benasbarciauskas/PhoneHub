import AppKit
import CoreGraphics
import PhoneHubCore

/// Live check for an on-screen (any Space) iPhone Mirroring phone window.
/// CGWindowList and NSRunningApplication lookups are safe off the main actor.
enum MirrorPresence {
    static func iosMirrorWindowVisible() -> Bool {
        guard NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity")
            .first != nil else { return false }

        guard let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
            as? [[String: Any]] else { return false }

        let candidates = info.compactMap { row -> MirrorWindowCandidate? in
            guard row[kCGWindowOwnerName as String] as? String == "iPhone Mirroring",
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else { return nil }
            return MirrorWindowCandidate(
                title: row[kCGWindowName as String] as? String ?? "",
                layer: row[kCGWindowLayer as String] as? Int ?? 0,
                width: width,
                height: height
            )
        }
        return containsLiveMirrorWindow(candidates)
    }
}
