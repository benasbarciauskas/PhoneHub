import Foundation
import Observation

public enum TextSourceStoreError: Error, LocalizedError, Equatable {
    case invalidName
    case invalidItems

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Text source name is required."
        case .invalidItems: return "A text source needs 1 to 10,000 non-empty items."
        }
    }
}

@Observable
@MainActor
public final class TextSourceStore {
    public private(set) var sources: [TextSource] = []
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let directory = directory ?? PresetStore.defaultDirectory()
        fileURL = directory.appendingPathComponent("text-sources.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    @discardableResult
    public func add(
        name: String,
        items: [String],
        mode: TextSourceMode
    ) throws -> TextSource {
        let source = TextSource(name: name, items: items, mode: mode)
        let validated = try validate(source)
        sources.append(validated)
        save()
        return validated
    }

    public func update(_ source: TextSource) {
        guard let validated = try? validate(source),
              let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = validated
        save()
    }

    public func resetCursor(_ sourceID: UUID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].cursor = 0
        save()
    }

    public func delete(_ sourceID: UUID) {
        sources.removeAll { $0.id == sourceID }
        save()
    }

    public func resolve(_ automation: Automation) throws -> TextSourceResolution {
        try resolveTextSourceBindings(
            steps: automation.steps,
            bindings: automation.textSourceBindings,
            sources: sources
        )
    }

    public func currentSteps(for automation: Automation) throws -> [AutomationStep] {
        try resolve(automation).steps
    }

    @discardableResult
    public func refresh(
        _ sourceID: UUID,
        using commandRunner: ShellCommandRunner = runShellCommand
    ) async throws -> Int {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            throw TextSourceResolutionError.missingSource(sourceID)
        }
        let source = sources[index]
        guard let command = source.refreshCommand,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return source.items.count
        }
        let result: CommandResult
        do {
            result = try await commandRunner(command, 30)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TextSourceRefreshError.commandFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            let detail = firstNonEmptyLine(result.stderr)
                ?? firstNonEmptyLine(String(data: result.stdout, encoding: .utf8) ?? "")
                ?? "exit status \(result.exitCode)"
            throw TextSourceRefreshError.commandFailed(
                "exit status \(result.exitCode): \(detail)"
            )
        }
        var refreshed = source
        refreshed.items = try parseTextSourceRefreshOutput(result.stdout)
        refreshed.cursor = 0
        let validated = try validate(refreshed)
        sources[index] = validated
        save()
        return validated.items.count
    }

    public func refreshSources(
        for automation: Automation,
        using commandRunner: ShellCommandRunner = runShellCommand
    ) async throws {
        let stepIDs = Set(automation.steps.map(\.id))
        var refreshed = Set<UUID>()
        for (stepID, reference) in automation.textSourceBindings where stepIDs.contains(stepID) {
            guard refreshed.insert(reference.sourceID).inserted else { continue }
            _ = try await refresh(reference.sourceID, using: commandRunner)
        }
    }

    /// Commits the cycle plan after a successful run. A cursor that changed
    /// since resolution is left untouched to avoid overwriting newer state.
    @discardableResult
    public func commit(_ resolution: TextSourceResolution) -> [String] {
        var messages: [String] = []
        var changed = false
        for advance in resolution.advances {
            guard let index = sources.firstIndex(where: { $0.id == advance.sourceID }),
                  sources[index].normalizedCursor == advance.fromCursor else { continue }
            sources[index].cursor = advance.toCursor
            changed = true
            if advance.wrapped {
                messages.append("Text source “\(advance.sourceName)” wrapped to the start.")
            }
        }
        if changed { save() }
        return messages
    }

    private func validate(_ source: TextSource) throws -> TextSource {
        var source = source
        source.name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.name.isEmpty else { throw TextSourceStoreError.invalidName }
        guard !source.items.isEmpty,
              source.items.count <= TextSourceParser.maximumItems,
              source.items.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TextSourceStoreError.invalidItems
        }
        source.cursor = source.normalizedCursor
        return source
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TextSource].self, from: data) else {
            sources = []
            return
        }
        sources = decoded.compactMap { try? validate($0) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sources) else { return }
        try? PresetStore.atomicWrite(data, to: fileURL)
    }

    private func firstNonEmptyLine(_ text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
