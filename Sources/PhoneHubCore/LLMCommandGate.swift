import Foundation

/// Whether an LLM-driven phone command may start for `device`.
/// iOS needs a live mirror window (that IS the visible screen the agent drives);
/// Android needs an adb-connected device. Pure — presence signals are injected.
public func llmCommandBlockReason(
    device: Device?,
    iosMirrorWindowVisible: Bool
) -> String? {
    guard let device else {
        return "Select a device first."
    }
    switch device.platform {
    case .ios:
        guard iosMirrorWindowVisible else {
            return "iPhone Mirroring is not showing \(device.model)'s screen. "
                + "Open iPhone Mirroring (or dock the device) before sending commands."
        }
        return nil
    case .android:
        guard device.isReady else {
            return "\(device.model) is not connected over adb (status: \(device.status))."
        }
        return nil
    }
}

/// True when a CGWindowList snapshot row set contains a live iPhone Mirroring
/// screen window: layer 0, phone-shaped (taller than wide), and not the
/// "Welcome to iPhone Mirroring" pairing window. Pure for testability.
public struct MirrorWindowCandidate: Equatable, Sendable {
    public let title: String
    public let layer: Int
    public let width: Double
    public let height: Double

    public init(title: String, layer: Int, width: Double, height: Double) {
        self.title = title
        self.layer = layer
        self.width = width
        self.height = height
    }
}

public func containsLiveMirrorWindow(_ windows: [MirrorWindowCandidate]) -> Bool {
    windows.contains { window in
        // Phone-shaped (≥1.5:1 tall) excludes the near-square "Welcome to
        // iPhone Mirroring" pairing window even when the title is unreadable
        // (reading other apps' window titles needs Screen Recording).
        window.layer == 0
            && window.height >= window.width * 1.5
            && window.width >= 200
            && !window.title.localizedCaseInsensitiveContains("welcome")
    }
}
