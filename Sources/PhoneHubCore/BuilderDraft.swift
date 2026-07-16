import Foundation

public struct BuilderDraft: Codable, Equatable, Sendable {
    public var platform: Platform?
    public var steps: [AutomationStep]
    public var textSourceBindings: [UUID: TextSourceRef]

    public init(
        platform: Platform? = nil,
        steps: [AutomationStep] = [],
        textSourceBindings: [UUID: TextSourceRef] = [:]
    ) {
        self.platform = platform
        self.steps = steps
        self.textSourceBindings = textSourceBindings
    }

    private enum CodingKeys: String, CodingKey {
        case platform, steps, textSourceBindings
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        platform = try values.decodeIfPresent(Platform.self, forKey: .platform)
        steps = try values.decodeIfPresent([AutomationStep].self, forKey: .steps) ?? []
        textSourceBindings = try values.decodeIfPresent(
            [UUID: TextSourceRef].self,
            forKey: .textSourceBindings
        ) ?? [:]
    }
}

public enum BuilderDraftError: Error, Equatable, LocalizedError {
    case platformMismatch(expected: Platform)

    public var errorDescription: String? {
        switch self {
        case .platformMismatch(let expected):
            return "This draft is pinned to \(expected.rawValue)."
        }
    }
}
