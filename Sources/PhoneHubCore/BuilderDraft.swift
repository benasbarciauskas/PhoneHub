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

public enum BuilderTimelineValidationError: Error, Equatable, LocalizedError {
    case emptyTimeline
    case missingPlatform
    case emptyTypeText(UUID)
    case emptyAIAction(UUID)
    case invalidPause(UUID)

    public var errorDescription: String? {
        switch self {
        case .emptyTimeline: return "Add at least one action to the timeline."
        case .missingPlatform: return "The draft is not pinned to a device platform."
        case .emptyTypeText: return "A Type text action needs literal text or a text source."
        case .emptyAIAction: return "An AI action needs a request."
        case .invalidPause: return "A pause must be between 0 and 3,600,000 milliseconds."
        }
    }
}

/// Pure boundary validation shared by the Builder's Save and Run actions.
/// Source resolution is included so deleted or malformed bindings fail before launch.
public func validateBuilderTimeline(
    _ draft: BuilderDraft,
    sources: [TextSource]
) throws {
    guard !draft.steps.isEmpty else { throw BuilderTimelineValidationError.emptyTimeline }
    guard draft.platform != nil else { throw BuilderTimelineValidationError.missingPlatform }

    for step in draft.steps {
        switch step {
        case let .typeText(id, text):
            if draft.textSourceBindings[id] == nil,
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BuilderTimelineValidationError.emptyTypeText(id)
            }
        case let .aiStep(id, prompt):
            if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BuilderTimelineValidationError.emptyAIAction(id)
            }
        case let .wait(id, milliseconds):
            if !(0...3_600_000).contains(milliseconds) {
                throw BuilderTimelineValidationError.invalidPause(id)
            }
        default: break
        }
    }
    _ = try resolveTextSourceBindings(
        steps: draft.steps,
        bindings: draft.textSourceBindings,
        sources: sources
    )
}
