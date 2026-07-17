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
    public var refreshCommand: String?

    public init(
        id: UUID = UUID(),
        name: String,
        items: [String],
        cursor: Int = 0,
        mode: TextSourceMode,
        refreshCommand: String? = nil
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.cursor = cursor
        self.mode = mode
        self.refreshCommand = refreshCommand
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, items, cursor, mode, refreshCommand
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        items = try values.decode([String].self, forKey: .items)
        cursor = try values.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
        mode = try values.decode(TextSourceMode.self, forKey: .mode)
        refreshCommand = try values.decodeIfPresent(String.self, forKey: .refreshCommand)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(items, forKey: .items)
        try values.encode(cursor, forKey: .cursor)
        try values.encode(mode, forKey: .mode)
        try values.encodeIfPresent(refreshCommand, forKey: .refreshCommand)
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

public enum TextSourceRefreshError: Error, Equatable, LocalizedError, Sendable {
    case invalidUTF8
    case emptyResult
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: return "Refresh command output is not valid UTF-8."
        case .emptyResult: return "Refresh command returned no text items."
        case .commandFailed(let detail): return "Refresh command failed: \(detail)"
        }
    }
}

public func parseTextSourceRefreshOutput(_ data: Data) throws -> [String] {
    guard let output = String(data: data, encoding: .utf8) else {
        throw TextSourceRefreshError.invalidUTF8
    }
    let items: [String]
    if let object = try? JSONSerialization.jsonObject(with: data),
       let array = object as? [Any],
       array.allSatisfy({ $0 is String }) {
        items = array.compactMap { $0 as? String }
    } else {
        items = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    let nonEmpty = items.filter {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !nonEmpty.isEmpty else { throw TextSourceRefreshError.emptyResult }
    return nonEmpty
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
