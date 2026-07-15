import Foundation
import Observation

@Observable
@MainActor
public final class AutomationStore {
    public private(set) var automations: [Automation] = []
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let directory = directory ?? PresetStore.defaultDirectory()
        fileURL = directory.appendingPathComponent("automations.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Automation].self, from: data) else {
            automations = []
            return
        }
        automations = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(automations) else { return }
        try? PresetStore.atomicWrite(data, to: fileURL)
    }

    public func add(_ automation: Automation) { automations.append(automation); save() }
    public func update(_ automation: Automation) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[index] = automation
        save()
    }
    public func delete(_ automation: Automation) {
        automations.removeAll { $0.id == automation.id }
        save()
    }
    @discardableResult
    public func duplicate(_ automation: Automation) -> Automation? {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return nil }
        var copy = automation
        copy.id = UUID()
        copy.name = "\(automation.name) copy"
        automations.insert(copy, at: index + 1)
        save()
        return copy
    }
    public func automations(for platform: Platform) -> [Automation] {
        automations.filter { $0.platform == platform }
    }
}
