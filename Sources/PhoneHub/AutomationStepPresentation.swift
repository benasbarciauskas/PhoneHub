import Foundation
import PhoneHubCore

func automationStepTitle(_ step: AutomationStep) -> String {
    switch step {
    case .launchApp: return "Launch app"
    case .tap: return "Tap"
    case .doubleTap: return "Double tap"
    case .longPress: return "Long press"
    case .typeText: return "Type text"
    case .pressKey: return "Press key"
    case .swipe: return "Swipe"
    case .pressHome: return "Press Home"
    case .pressBack: return "Press Back"
    case .pressAppSwitcher: return "App Switcher"
    case .scrollTo: return "Scroll to"
    case .openURL: return "Open URL"
    case .wait: return "Pause"
    case .aiStep: return "AI action"
    case .switchDevice: return "Switch device"
    }
}

func automationStepIcon(_ step: AutomationStep) -> String {
    switch step {
    case .launchApp: return "app"
    case .tap, .doubleTap, .longPress: return "hand.tap"
    case .typeText: return "keyboard"
    case .pressKey: return "command"
    case .swipe: return "arrow.up.and.down"
    case .pressHome: return "house"
    case .pressBack: return "chevron.backward"
    case .pressAppSwitcher: return "rectangle.3.group"
    case .scrollTo: return "text.magnifyingglass"
    case .openURL: return "link"
    case .wait: return "clock"
    case .aiStep: return "sparkles"
    case .switchDevice: return "arrow.triangle.2.circlepath.iphone"
    }
}

func automationStepSummary(_ step: AutomationStep) -> String {
    switch step {
    case let .launchApp(_, name): return name
    case let .tap(_, label, x, y), let .doubleTap(_, label, x, y):
        return pointSummary(label: label, x: x, y: y)
    case let .longPress(_, label, x, y, duration):
        return "\(pointSummary(label: label, x: x, y: y)) · \(duration) ms"
    case let .typeText(_, text): return text.isEmpty ? "No text" : text
    case let .pressKey(_, key): return key
    case let .swipe(_, direction): return direction.capitalized
    case .pressHome, .pressBack, .pressAppSwitcher: return ""
    case let .scrollTo(_, text, direction): return "\(text) · \(direction)"
    case let .openURL(_, url): return url
    case let .wait(_, ms): return "\(ms) ms"
    case let .aiStep(_, prompt): return prompt.isEmpty ? "No request" : prompt
    case let .switchDevice(_, ref): return ref
    }
}

private func pointSummary(label: String?, x: Double?, y: Double?) -> String {
    if let label, !label.isEmpty { return label }
    if let x, let y { return "(\(Int(x.rounded())), \(Int(y.rounded())))" }
    return "Target not set"
}
