import Foundation

public enum Platform: String, Sendable, Codable {
    case ios
    case android
}

public struct Device: Identifiable, Hashable, Sendable {
    public let id: String        // udid / serial
    public let platform: Platform
    public var model: String
    public var osVersion: String
    public var status: String    // "device", "unauthorized", "offline", ...

    public init(id: String, platform: Platform, model: String, osVersion: String, status: String) {
        self.id = id
        self.platform = platform
        self.model = model
        self.osVersion = osVersion
        self.status = status
    }

    public var isReady: Bool { status == "device" }
}

/// Resolve a stored device ref to a connected device.
/// Prefers case-insensitive match on `model`, then exact match on optional labels (device id → user label).
public func resolveDeviceRef(_ ref: String, devices: [Device],
                             labels: [String: String] = [:]) -> Device? {
    let needle = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return nil }
    if let byModel = devices.first(where: {
        $0.model.compare(needle, options: .caseInsensitive) == .orderedSame
    }) {
        return byModel
    }
    return devices.first(where: { labels[$0.id] == needle })
}
