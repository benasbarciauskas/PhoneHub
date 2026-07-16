import Foundation

public enum AnyCodableValue: Codable, Equatable, Sendable {
    case string(String)
    case double(Double)
    case int(Int)
    case bool(Bool)
    case null

    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .double(let value): return value
        case .int(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct ToolInvocation: Equatable, Sendable {
    public let tool: String
    public let arguments: [String: AnyCodableValue]

    public init(tool: String, arguments: [String: AnyCodableValue]) {
        self.tool = tool
        self.arguments = arguments
    }
}

public enum AutomationStepExecutionError: Error, Equatable {
    case needsProbe
    case invalidSerial
}

public func toolInvocation(for step: AutomationStep, platform: Platform,
                           serial: String?, binding: Automation.Binding?) throws -> ToolInvocation? {
    let invocation: ToolInvocation?
    switch step {
    case let .launchApp(_, name):
        invocation = ToolInvocation(tool: "launch_app", arguments: ["app_name": .string(name)])
    case let .tap(_, _, x, y):
        invocation = try pointInvocation(tool: "tap", x: x, y: y, binding: binding)
    case let .doubleTap(_, _, x, y):
        invocation = try pointInvocation(tool: "double_tap", x: x, y: y, binding: binding)
    case let .longPress(_, _, x, y, durationMs):
        let point = try pointInvocation(tool: "long_press", x: x, y: y, binding: binding)
        var arguments = point.arguments
        arguments["duration_ms"] = .int(durationMs)
        invocation = ToolInvocation(tool: point.tool, arguments: arguments)
    case let .typeText(_, text):
        invocation = ToolInvocation(tool: "type_text", arguments: ["text": .string(text)])
    case let .pressKey(_, key):
        invocation = ToolInvocation(tool: "press_key", arguments: ["key": .string(key)])
    case let .swipe(_, direction):
        invocation = ToolInvocation(tool: "swipe", arguments: ["direction": .string(direction)])
    case .pressHome:
        invocation = ToolInvocation(tool: "press_home", arguments: [:])
    case .pressBack:
        invocation = ToolInvocation(tool: "press_back", arguments: [:])
    case .pressAppSwitcher:
        invocation = ToolInvocation(tool: "press_app_switcher", arguments: [:])
    case let .scrollTo(_, text, direction):
        invocation = ToolInvocation(tool: "scroll_to", arguments: [
            "text": .string(text), "direction": .string(direction)
        ])
    case let .openURL(_, url):
        invocation = ToolInvocation(tool: "open_url", arguments: ["url": .string(url)])
    case .wait, .aiStep:
        return nil
    }

    guard let invocation else { return nil }
    if platform == .android {
        guard let serial, isValidSerial(serial) else { throw AutomationStepExecutionError.invalidSerial }
        var arguments = invocation.arguments
        arguments["serial"] = .string(serial)
        return ToolInvocation(tool: invocation.tool, arguments: arguments)
    }
    return invocation
}

private func pointInvocation(tool: String, x: Double?, y: Double?,
                             binding: Automation.Binding?) throws -> ToolInvocation {
    let resolvedX = binding?.x ?? x
    let resolvedY = binding?.y ?? y
    guard let resolvedX, let resolvedY else { throw AutomationStepExecutionError.needsProbe }
    return ToolInvocation(tool: tool, arguments: ["x": .double(resolvedX), "y": .double(resolvedY)])
}
