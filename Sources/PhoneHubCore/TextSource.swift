import Foundation

public enum TextSourceMode: String, Codable, CaseIterable, Sendable {
    case `static`
    case cycle
}

public struct TextSource: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [String]
    public var cursor: Int
    public var mode: TextSourceMode

    public init(
        id: UUID = UUID(),
        name: String,
        items: [String],
        cursor: Int = 0,
        mode: TextSourceMode
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.cursor = cursor
        self.mode = mode
    }

    public var normalizedCursor: Int {
        guard !items.isEmpty else { return 0 }
        return ((cursor % items.count) + items.count) % items.count
    }

    public var currentItem: String? {
        guard !items.isEmpty else { return nil }
        return items[normalizedCursor]
    }
}

public struct TextSourceRef: Codable, Equatable, Sendable {
    public var sourceID: UUID
    public init(sourceID: UUID) { self.sourceID = sourceID }
}

public struct TextSourceAdvance: Equatable, Sendable {
    public let sourceID: UUID
    public let sourceName: String
    public let fromCursor: Int
    public let toCursor: Int
    public let wrapped: Bool

    public init(
        sourceID: UUID,
        sourceName: String,
        fromCursor: Int,
        toCursor: Int,
        wrapped: Bool
    ) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.fromCursor = fromCursor
        self.toCursor = toCursor
        self.wrapped = wrapped
    }
}

public struct TextSourceResolution: Equatable, Sendable {
    public let steps: [AutomationStep]
    public let advances: [TextSourceAdvance]

    public init(steps: [AutomationStep], advances: [TextSourceAdvance]) {
        self.steps = steps
        self.advances = advances
    }
}

public enum TextSourceResolutionError: Error, Equatable, LocalizedError, Sendable {
    case missingSource(UUID)
    case emptySource(UUID)
    case bindingRequiresTypeText(UUID)

    public var errorDescription: String? {
        switch self {
        case .missingSource: return "A text source used by this automation no longer exists."
        case .emptySource: return "A text source used by this automation contains no items."
        case .bindingRequiresTypeText:
            return "A text source can only be bound to a Type text step."
        }
    }
}

public func resolveTextSourceBindings(
    steps: [AutomationStep],
    bindings: [UUID: TextSourceRef],
    sources: [TextSource]
) throws -> TextSourceResolution {
    var sourcesByID: [UUID: TextSource] = [:]
    for source in sources { sourcesByID[source.id] = source }
    let stepIDs = Set(steps.map(\.id))
    for (stepID, _) in bindings where stepIDs.contains(stepID) {
        guard let step = steps.first(where: { $0.id == stepID }),
              case .typeText = step else {
            throw TextSourceResolutionError.bindingRequiresTypeText(stepID)
        }
    }

    var advances: [TextSourceAdvance] = []
    var plannedSources = Set<UUID>()
    let resolved = try steps.map { step -> AutomationStep in
        guard case let .typeText(id, _) = step,
              let reference = bindings[id] else { return step }
        guard let source = sourcesByID[reference.sourceID] else {
            throw TextSourceResolutionError.missingSource(reference.sourceID)
        }
        guard let item = source.currentItem else {
            throw TextSourceResolutionError.emptySource(source.id)
        }
        if source.mode == .cycle, plannedSources.insert(source.id).inserted {
            let from = source.normalizedCursor
            let to = (from + 1) % source.items.count
            advances.append(TextSourceAdvance(
                sourceID: source.id,
                sourceName: source.name,
                fromCursor: from,
                toCursor: to,
                wrapped: to == 0
            ))
        }
        return .typeText(id: id, text: item)
    }
    return TextSourceResolution(steps: resolved, advances: advances)
}
