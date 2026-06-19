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
