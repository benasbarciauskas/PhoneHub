import Foundation

public enum AutomationStep: Codable, Equatable, Identifiable, Sendable {
    case launchApp(id: UUID, name: String)
    case tap(id: UUID, label: String?, x: Double?, y: Double?)
    case doubleTap(id: UUID, label: String?, x: Double?, y: Double?)
    case longPress(id: UUID, label: String?, x: Double?, y: Double?, durationMs: Int)
    case typeText(id: UUID, text: String)
    case pressKey(id: UUID, key: String)
    case swipe(id: UUID, direction: String)
    case pressHome(id: UUID)
    case pressBack(id: UUID)
    case pressAppSwitcher(id: UUID)
    case scrollTo(id: UUID, text: String, direction: String)
    case openURL(id: UUID, url: String)
    case wait(id: UUID, ms: Int)
    case aiStep(id: UUID, prompt: String)
    /// Switch subsequent steps to another connected device (model name or user label).
    case switchDevice(id: UUID, deviceRef: String)

    public var id: UUID {
        switch self {
        case let .launchApp(id, _), let .tap(id, _, _, _), let .doubleTap(id, _, _, _),
             let .longPress(id, _, _, _, _), let .typeText(id, _), let .pressKey(id, _),
             let .swipe(id, _), let .pressHome(id), let .pressBack(id),
             let .pressAppSwitcher(id), let .scrollTo(id, _, _), let .openURL(id, _),
             let .wait(id, _), let .aiStep(id, _), let .switchDevice(id, _):
            return id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, name, label, x, y, durationMs, text, key, direction, url, ms, prompt, deviceRef
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let type = try values.decode(String.self, forKey: .type)
        let id = try values.decode(UUID.self, forKey: .id)
        switch type {
        case "launchApp": self = .launchApp(id: id, name: try values.decode(String.self, forKey: .name))
        case "tap": self = .tap(id: id, label: try values.decodeIfPresent(String.self, forKey: .label), x: try values.decodeIfPresent(Double.self, forKey: .x), y: try values.decodeIfPresent(Double.self, forKey: .y))
        case "doubleTap": self = .doubleTap(id: id, label: try values.decodeIfPresent(String.self, forKey: .label), x: try values.decodeIfPresent(Double.self, forKey: .x), y: try values.decodeIfPresent(Double.self, forKey: .y))
        case "longPress": self = .longPress(id: id, label: try values.decodeIfPresent(String.self, forKey: .label), x: try values.decodeIfPresent(Double.self, forKey: .x), y: try values.decodeIfPresent(Double.self, forKey: .y), durationMs: try values.decode(Int.self, forKey: .durationMs))
        case "typeText": self = .typeText(id: id, text: try values.decode(String.self, forKey: .text))
        case "pressKey": self = .pressKey(id: id, key: try values.decode(String.self, forKey: .key))
        case "swipe": self = .swipe(id: id, direction: try values.decode(String.self, forKey: .direction))
        case "pressHome": self = .pressHome(id: id)
        case "pressBack": self = .pressBack(id: id)
        case "pressAppSwitcher": self = .pressAppSwitcher(id: id)
        case "scrollTo": self = .scrollTo(id: id, text: try values.decode(String.self, forKey: .text), direction: try values.decode(String.self, forKey: .direction))
        case "openURL": self = .openURL(id: id, url: try values.decode(String.self, forKey: .url))
        case "wait": self = .wait(id: id, ms: try values.decode(Int.self, forKey: .ms))
        case "aiStep": self = .aiStep(id: id, prompt: try values.decode(String.self, forKey: .prompt))
        case "switchDevice": self = .switchDevice(id: id, deviceRef: try values.decode(String.self, forKey: .deviceRef))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: values,
                                                    debugDescription: "Unknown automation step type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        switch self {
        case let .launchApp(_, name): try values.encode("launchApp", forKey: .type); try values.encode(name, forKey: .name)
        case let .tap(_, label, x, y): try encodePoint("tap", label, x, y, into: &values)
        case let .doubleTap(_, label, x, y): try encodePoint("doubleTap", label, x, y, into: &values)
        case let .longPress(_, label, x, y, durationMs): try encodePoint("longPress", label, x, y, into: &values); try values.encode(durationMs, forKey: .durationMs)
        case let .typeText(_, text): try values.encode("typeText", forKey: .type); try values.encode(text, forKey: .text)
        case let .pressKey(_, key): try values.encode("pressKey", forKey: .type); try values.encode(key, forKey: .key)
        case let .swipe(_, direction): try values.encode("swipe", forKey: .type); try values.encode(direction, forKey: .direction)
        case .pressHome: try values.encode("pressHome", forKey: .type)
        case .pressBack: try values.encode("pressBack", forKey: .type)
        case .pressAppSwitcher: try values.encode("pressAppSwitcher", forKey: .type)
        case let .scrollTo(_, text, direction): try values.encode("scrollTo", forKey: .type); try values.encode(text, forKey: .text); try values.encode(direction, forKey: .direction)
        case let .openURL(_, url): try values.encode("openURL", forKey: .type); try values.encode(url, forKey: .url)
        case let .wait(_, ms): try values.encode("wait", forKey: .type); try values.encode(ms, forKey: .ms)
        case let .aiStep(_, prompt): try values.encode("aiStep", forKey: .type); try values.encode(prompt, forKey: .prompt)
        case let .switchDevice(_, deviceRef): try values.encode("switchDevice", forKey: .type); try values.encode(deviceRef, forKey: .deviceRef)
        }
    }

    private func encodePoint(_ type: String, _ label: String?, _ x: Double?, _ y: Double?,
                             into values: inout KeyedEncodingContainer<CodingKeys>) throws {
        try values.encode(type, forKey: .type)
        try values.encodeIfPresent(label, forKey: .label)
        try values.encodeIfPresent(x, forKey: .x)
        try values.encodeIfPresent(y, forKey: .y)
    }
}

public enum LoopMode: Codable, Equatable, Sendable {
    case once
    case times(Int)
    case forever
}

public struct Automation: Codable, Equatable, Identifiable, Sendable {
    public struct Binding: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public var id: UUID
    public var name: String
    public var platform: Platform
    public var steps: [AutomationStep]
    public var rawSteps: [AutomationStep]?
    public var useCondensed: Bool
    public var loop: LoopMode
    public var sharedCoordinates: Bool
    public var bindings: [String: [String: Binding]]
    /// Parallel metadata keeps source-bound text compatible with old `.typeText`
    /// step JSON and with community formats that only understand literal text.
    public var textSourceBindings: [UUID: TextSourceRef]
    public var pinned: Bool
    public var sourceGoal: String?

    public init(id: UUID = UUID(), name: String, platform: Platform, steps: [AutomationStep],
                rawSteps: [AutomationStep]? = nil, useCondensed: Bool = true,
                loop: LoopMode = .once, sharedCoordinates: Bool = false,
                bindings: [String: [String: Binding]] = [:], pinned: Bool = false,
                textSourceBindings: [UUID: TextSourceRef] = [:],
                sourceGoal: String? = nil) {
        self.id = id; self.name = name; self.platform = platform; self.steps = steps
        self.rawSteps = rawSteps; self.useCondensed = useCondensed; self.loop = loop
        self.sharedCoordinates = sharedCoordinates; self.bindings = bindings
        self.textSourceBindings = textSourceBindings
        self.pinned = pinned; self.sourceGoal = sourceGoal
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, platform, steps, rawSteps, useCondensed, loop
        case sharedCoordinates, bindings, textSourceBindings, pinned, sourceGoal
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        platform = try values.decode(Platform.self, forKey: .platform)
        steps = try values.decode([AutomationStep].self, forKey: .steps)
        rawSteps = try values.decodeIfPresent([AutomationStep].self, forKey: .rawSteps)
        useCondensed = try values.decodeIfPresent(Bool.self, forKey: .useCondensed) ?? true
        loop = try values.decodeIfPresent(LoopMode.self, forKey: .loop) ?? .once
        sharedCoordinates = try values.decodeIfPresent(Bool.self, forKey: .sharedCoordinates) ?? false
        bindings = try values.decodeIfPresent(
            [String: [String: Binding]].self,
            forKey: .bindings
        ) ?? [:]
        textSourceBindings = try values.decodeIfPresent(
            [UUID: TextSourceRef].self,
            forKey: .textSourceBindings
        ) ?? [:]
        pinned = try values.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        sourceGoal = try values.decodeIfPresent(String.self, forKey: .sourceGoal)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(platform, forKey: .platform)
        try values.encode(steps, forKey: .steps)
        try values.encodeIfPresent(rawSteps, forKey: .rawSteps)
        try values.encode(useCondensed, forKey: .useCondensed)
        try values.encode(loop, forKey: .loop)
        try values.encode(sharedCoordinates, forKey: .sharedCoordinates)
        try values.encode(bindings, forKey: .bindings)
        try values.encode(textSourceBindings, forKey: .textSourceBindings)
        try values.encode(pinned, forKey: .pinned)
        try values.encodeIfPresent(sourceGoal, forKey: .sourceGoal)
    }
}
