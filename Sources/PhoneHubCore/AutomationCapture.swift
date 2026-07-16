import Foundation

public struct CapturedCall: Codable, Equatable, Sendable {
    public let tool: String
    public let rawInput: String

    public init(tool: String, rawInput: String) {
        self.tool = tool
        self.rawInput = rawInput
    }
}

public func automationDraft(from calls: [CapturedCall], platform: Platform,
                            name: String, sourceGoal: String?) -> Automation {
    let actions = automationSteps(from: calls)
    var timeline: [AutomationStep] = []
    for (index, action) in actions.enumerated() {
        if index > 0 { timeline.append(.wait(id: UUID(), ms: automationSettleMilliseconds)) }
        timeline.append(action)
    }
    return Automation(name: name, platform: platform, steps: timeline,
                      rawSteps: timeline, useCondensed: false, sourceGoal: sourceGoal)
}

/// Maps captured mutating phone calls without adding timeline settle waits.
/// Observation calls are deliberately excluded so builder turns can require
/// exactly one resulting action even when the agent inspected the screen first.
public func automationSteps(from calls: [CapturedCall]) -> [AutomationStep] {
    calls.compactMap(step(from:))
}

private func step(from call: CapturedCall) -> AutomationStep? {
    let tool = StreamJSONParser.shortToolName(call.tool).lowercased()
    if tool == "describe_screen" || tool == "screenshot" || tool == "status"
        || tool.hasPrefix("list_") { return nil }
    guard let data = call.rawInput.data(using: .utf8),
          let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let id = UUID()
    switch tool {
    case "launch_app":
        guard let name = string(arguments, "app_name", "name") else { return nil }
        return .launchApp(id: id, name: name)
    case "tap":
        return pointStep(id: id, arguments: arguments) { .tap(id: id, label: $0, x: $1, y: $2) }
    case "double_tap":
        return pointStep(id: id, arguments: arguments) { .doubleTap(id: id, label: $0, x: $1, y: $2) }
    case "long_press":
        let duration = integer(arguments["duration_ms"]) ?? integer(arguments["durationMs"]) ?? 800
        return pointStep(id: id, arguments: arguments) {
            .longPress(id: id, label: $0, x: $1, y: $2, durationMs: duration)
        }
    case "type_text":
        guard let text = string(arguments, "text") else { return nil }
        return .typeText(id: id, text: text)
    case "press_key":
        guard let key = string(arguments, "key") else { return nil }
        return .pressKey(id: id, key: key)
    case "swipe":
        guard let direction = string(arguments, "direction") else { return nil }
        return .swipe(id: id, direction: direction)
    case "press_home": return .pressHome(id: id)
    case "press_back": return .pressBack(id: id)
    case "press_app_switcher": return .pressAppSwitcher(id: id)
    case "scroll_to":
        guard let text = string(arguments, "text"),
              let direction = string(arguments, "direction") else { return nil }
        return .scrollTo(id: id, text: text, direction: direction)
    case "open_url":
        guard let url = string(arguments, "url") else { return nil }
        return .openURL(id: id, url: url)
    default: return nil
    }
}

private func pointStep(id: UUID, arguments: [String: Any],
                       build: (String?, Double?, Double?) -> AutomationStep) -> AutomationStep? {
    let label = string(arguments, "label", "text", "target")
    let x = number(arguments["x"])
    let y = number(arguments["y"])
    guard label != nil || (x != nil && y != nil) else { return nil }
    return build(label, x, y)
}

private func string(_ arguments: [String: Any], _ keys: String...) -> String? {
    for key in keys {
        if let value = arguments[key] as? String, !value.isEmpty { return value }
    }
    return nil
}

private func number(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    return number.doubleValue
}

private func integer(_ value: Any?) -> Int? { number(value).map(Int.init) }
