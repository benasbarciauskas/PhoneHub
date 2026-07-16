import Foundation
import Observation

@Observable
@MainActor
public final class BuilderDraftStore {
    public private(set) var draft = BuilderDraft()
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let directory = directory ?? PresetStore.defaultDirectory()
        fileURL = directory.appendingPathComponent("builder-draft.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    public func append(_ step: AutomationStep, platform: Platform) throws {
        try insert(step, at: draft.steps.count, platform: platform)
    }

    public func insert(_ step: AutomationStep, at index: Int, platform: Platform) throws {
        try requirePlatform(platform)
        draft.platform = draft.platform ?? platform
        draft.steps.insert(step, at: max(0, min(index, draft.steps.count)))
        save()
    }

    public func update(_ step: AutomationStep) {
        guard let index = draft.steps.firstIndex(where: { $0.id == step.id }) else { return }
        draft.steps[index] = step
        if case .typeText = step {} else { draft.textSourceBindings[step.id] = nil }
        save()
    }

    public func setTextSource(_ sourceID: UUID?, forStepID stepID: UUID) {
        guard let step = draft.steps.first(where: { $0.id == stepID }),
              case .typeText = step else { return }
        draft.textSourceBindings[stepID] = sourceID.map(TextSourceRef.init(sourceID:))
        save()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = IndexSet(source.filter { draft.steps.indices.contains($0) })
        let moved = valid.sorted().map { draft.steps[$0] }
        for index in valid.sorted(by: >) { draft.steps.remove(at: index) }
        let adjusted = destination - valid.filter { $0 < destination }.count
        draft.steps.insert(
            contentsOf: moved,
            at: max(0, min(adjusted, draft.steps.count))
        )
        save()
    }

    public func delete(at offsets: IndexSet) {
        let valid = offsets.filter { draft.steps.indices.contains($0) }
        let removedIDs = valid.map { draft.steps[$0].id }
        for index in valid.sorted(by: >) { draft.steps.remove(at: index) }
        for id in removedIDs { draft.textSourceBindings[id] = nil }
        if draft.steps.isEmpty {
            draft.platform = nil
            draft.textSourceBindings = [:]
        }
        save()
    }

    public func clear() {
        draft = BuilderDraft()
        save()
    }

    public func automation(named name: String) -> Automation? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let platform = draft.platform, !draft.steps.isEmpty else { return nil }
        return Automation(
            name: name,
            platform: platform,
            steps: draft.steps,
            textSourceBindings: draft.textSourceBindings
        )
    }

    private func requirePlatform(_ platform: Platform) throws {
        if let expected = draft.platform, expected != platform {
            throw BuilderDraftError.platformMismatch(expected: expected)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              var decoded = try? JSONDecoder().decode(BuilderDraft.self, from: data) else {
            draft = BuilderDraft()
            return
        }
        let stepIDs = Set(decoded.steps.map(\.id))
        decoded.textSourceBindings = decoded.textSourceBindings.filter { stepIDs.contains($0.key) }
        if decoded.steps.isEmpty { decoded.platform = nil }
        draft = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(draft) else { return }
        try? PresetStore.atomicWrite(data, to: fileURL)
    }
}
