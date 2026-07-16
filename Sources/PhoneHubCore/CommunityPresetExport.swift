import Foundation

public enum CommunityPresetExportError: LocalizedError, Equatable {
    case missingName
    case missingApp
    case emptySteps
    case invalidPathPart(String)
    case invalidStep(index: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingName:
            return "Preset name is required."
        case .missingApp:
            return "App name is required."
        case .emptySteps:
            return "At least one step is required."
        case let .invalidPathPart(field):
            return "The \(field) must contain at least one letter or number."
        case let .invalidStep(index, reason):
            return "Step at index \(index) \(reason)"
        }
    }
}

public func communityPresetJSON(
    name: String,
    platform: Platform,
    app: String,
    steps: [AutomationStep]
) throws -> Data {
    try validateTopLevel(name: name, app: app, steps: steps)
    let mappedSteps = try steps.enumerated().map { index, step in
        try communityStep(step, index: index)
    }
    let root = OrderedJSON.object([
        ("name", .string(name)),
        ("platform", .string(platform.rawValue)),
        ("app", .string(app)),
        ("steps", .array(mappedSteps)),
    ])
    return Data((root.rendered() + "\n").utf8)
}

public func communityPresetJSON(
    name: String,
    platform: Platform,
    app: String,
    preset: Preset
) throws -> Data {
    try communityPresetJSON(
        name: name,
        platform: platform,
        app: app,
        steps: [.aiStep(id: UUID(), prompt: preset.goal)]
    )
}

public func slug(_ string: String) -> String {
    let folded = string
        .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
    var result = ""
    var needsSeparator = false

    for scalar in folded.unicodeScalars {
        let isASCIIAlphaNumeric = (48...57).contains(scalar.value) || (97...122).contains(scalar.value)
        if isASCIIAlphaNumeric {
            if needsSeparator, !result.isEmpty { result.append("-") }
            result.unicodeScalars.append(scalar)
            needsSeparator = false
        } else if !result.isEmpty {
            needsSeparator = true
        }
    }
    return result
}

public func communityPresetPath(platform: Platform, app: String, name: String) throws -> String {
    guard !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CommunityPresetExportError.missingApp
    }
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CommunityPresetExportError.missingName
    }
    let appSlug = slug(app)
    let presetSlug = slug(name)
    guard !appSlug.isEmpty else {
        throw CommunityPresetExportError.invalidPathPart("app name")
    }
    guard !presetSlug.isEmpty else {
        throw CommunityPresetExportError.invalidPathPart("preset name")
    }
    return "presets/\(platform.rawValue)/\(appSlug)/\(presetSlug).json"
}

private func validateTopLevel(name: String, app: String, steps: [AutomationStep]) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CommunityPresetExportError.missingName
    }
    guard !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CommunityPresetExportError.missingApp
    }
    guard !steps.isEmpty else { throw CommunityPresetExportError.emptySteps }
}

private func communityStep(_ step: AutomationStep, index: Int) throws -> OrderedJSON {
    switch step {
    case let .launchApp(_, name):
        try requireNonEmpty(name, index: index, field: "app name")
        return .object([("type", .string("launchApp")), ("name", .string(name))])
    case let .tap(_, label, _, _):
        return try pointStep(type: "tap", label: label, index: index)
    case let .doubleTap(_, label, _, _):
        return try pointStep(type: "doubleTap", label: label, index: index)
    case let .longPress(_, label, _, _, durationMs):
        guard durationMs >= 0 else {
            throw invalidStep(index, "has a negative duration.")
        }
        var fields = try pointFields(type: "longPress", label: label, index: index)
        fields.append(("durationMs", .integer(durationMs)))
        return .object(fields)
    case let .typeText(_, text):
        return .object([("type", .string("typeText")), ("text", .string(text))])
    case let .pressKey(_, key):
        try requireNonEmpty(key, index: index, field: "key")
        return .object([("type", .string("pressKey")), ("key", .string(key))])
    case let .swipe(_, direction):
        try requireDirection(direction, index: index)
        return .object([("type", .string("swipe")), ("direction", .string(direction))])
    case .pressHome:
        return .object([("type", .string("pressHome"))])
    case .pressBack:
        return .object([("type", .string("pressBack"))])
    case .pressAppSwitcher:
        return .object([("type", .string("pressAppSwitcher"))])
    case let .scrollTo(_, text, direction):
        try requireNonEmpty(text, index: index, field: "text")
        try requireDirection(direction, index: index)
        return .object([
            ("type", .string("scrollTo")),
            ("text", .string(text)),
            ("direction", .string(direction)),
        ])
    case let .openURL(_, url):
        guard validAbsoluteURL(url) else {
            throw invalidStep(index, "requires a valid absolute URL.")
        }
        return .object([("type", .string("openURL")), ("url", .string(url))])
    case let .wait(_, ms):
        guard ms >= 0 else { throw invalidStep(index, "has a negative duration.") }
        return .object([("type", .string("wait")), ("ms", .integer(ms))])
    case let .aiStep(_, prompt):
        try requireNonEmpty(prompt, index: index, field: "prompt")
        return .object([("type", .string("aiStep")), ("prompt", .string(prompt))])
    case .switchDevice:
        throw invalidStep(index, "uses switchDevice, which is device-specific and not shareable.")
    }
}

private func pointStep(type: String, label: String?, index: Int) throws -> OrderedJSON {
    .object(try pointFields(type: type, label: label, index: index))
}

private func pointFields(type: String, label: String?, index: Int) throws -> [(String, OrderedJSON)] {
    guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalidStep(index, "(\(type)) requires a non-empty label; coordinate-only actions are not shareable.")
    }
    return [("type", .string(type)), ("label", .string(label))]
}

private func requireNonEmpty(_ value: String, index: Int, field: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalidStep(index, "requires a non-empty \(field).")
    }
}

private func requireDirection(_ direction: String, index: Int) throws {
    guard ["up", "down", "left", "right"].contains(direction) else {
        throw invalidStep(index, "has an invalid direction; use up, down, left, or right.")
    }
}

private func validAbsoluteURL(_ value: String) -> Bool {
    guard value.unicodeScalars.allSatisfy({
        !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
    }),
          let components = URLComponents(string: value),
          let scheme = components.scheme,
          !scheme.isEmpty else { return false }
    return scheme.unicodeScalars.first.map(CharacterSet.letters.contains) == true
}

private func invalidStep(_ index: Int, _ reason: String) -> CommunityPresetExportError {
    .invalidStep(index: index, reason: reason)
}

private indirect enum OrderedJSON {
    case string(String)
    case integer(Int)
    case array([OrderedJSON])
    case object([(String, OrderedJSON)])

    func rendered(level: Int = 0) -> String {
        switch self {
        case let .string(value):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(decoding: try! encoder.encode(value), as: UTF8.self)
        case let .integer(value):
            return String(value)
        case let .array(values):
            guard !values.isEmpty else { return "[]" }
            let body = values.map { indent(level + 1) + $0.rendered(level: level + 1) }
                .joined(separator: ",\n")
            return "[\n\(body)\n\(indent(level))]"
        case let .object(fields):
            guard !fields.isEmpty else { return "{}" }
            let body = fields.map { key, value in
                let encodedKey = OrderedJSON.string(key).rendered()
                return indent(level + 1) + encodedKey + ": " + value.rendered(level: level + 1)
            }.joined(separator: ",\n")
            return "{\n\(body)\n\(indent(level))}"
        }
    }
}

private func indent(_ level: Int) -> String {
    String(repeating: "  ", count: level)
}
