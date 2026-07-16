import Foundation

public enum ScreenCapturePolicy: String, Codable, CaseIterable, Sendable {
    case duringRunsOnly
    case disabled
    case always

    public var displayName: String {
        switch self {
        case .duringRunsOnly: return "During Runs Only"
        case .disabled: return "Disabled"
        case .always: return "Always"
        }
    }

    public var description: String {
        switch self {
        case .duringRunsOnly:
            return "Allow capture only while a preset, chat turn, or automation is running."
        case .disabled:
            return "Never allow screenshots or screen recordings."
        case .always:
            return "Allow capture whenever a phone-control agent requests it."
        }
    }
}

public struct ScreenCaptureDecision: Equatable, Sendable {
    public let allowsCapture: Bool
    public let deniedTools: [String]
    public let logMessage: String?

    public init(allowsCapture: Bool, deniedTools: [String], logMessage: String?) {
        self.allowsCapture = allowsCapture
        self.deniedTools = deniedTools
        self.logMessage = logMessage
    }
}

public func screenCaptureDecision(
    policy: ScreenCapturePolicy,
    isRunActive: Bool
) -> ScreenCaptureDecision {
    let allowed: Bool
    switch policy {
    case .duringRunsOnly: allowed = isRunActive
    case .disabled: allowed = false
    case .always: allowed = true
    }

    guard !allowed else {
        return ScreenCaptureDecision(allowsCapture: true, deniedTools: [], logMessage: nil)
    }

    let message: String
    switch policy {
    case .duringRunsOnly:
        message = "screen capture is limited to active runs — using text description only"
    case .disabled:
        message = "screen capture disabled in settings — using text description only"
    case .always:
        preconditionFailure("Always-on screen capture cannot be denied.")
    }

    return ScreenCaptureDecision(
        allowsCapture: false,
        deniedTools: ["screenshot", "start_recording", "stop_recording"],
        logMessage: message
    )
}
