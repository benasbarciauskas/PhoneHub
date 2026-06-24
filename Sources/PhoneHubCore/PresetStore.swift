import Foundation
import Observation

/// Loads/saves presets to `~/Library/Application Support/PhoneHub/presets.json`.
/// Seeds built-ins on first run. Tolerates a malformed file by ignoring bad
/// entries rather than crashing. Atomic writes via temp file + rename.
@Observable
@MainActor
public final class PresetStore {
    public private(set) var presets: [Preset] = []

    private let fileURL: URL

    /// - Parameter directory: override for tests; defaults to Application Support.
    public init(directory: URL? = nil) {
        let dir = directory ?? PresetStore.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("presets.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    public nonisolated static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PhoneHub", isDirectory: true)
    }

    // MARK: - Load / save

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            presets = Preset.builtIns
            save()
            return
        }
        presets = PresetStore.decodeTolerant(data)
    }

    /// Decode an array of presets, skipping any entries that fail to decode
    /// (so one corrupt entry can't wipe the rest or crash the app).
    public nonisolated static func decodeTolerant(_ data: Data) -> [Preset] {
        // Fast path: a fully valid file.
        if let all = try? JSONDecoder().decode([Preset].self, from: data) {
            return all
        }
        // Tolerant path: decode element-by-element, dropping bad ones.
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        let decoder = JSONDecoder()
        return raw.compactMap { element -> Preset? in
            guard let elementData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? decoder.decode(Preset.self, from: elementData)
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(presets)
            try PresetStore.atomicWrite(data, to: fileURL)
        } catch {
            // Non-fatal: keep the in-memory list; surface nothing to the user.
        }
    }

    /// Write to a temp file in the same directory, then atomically rename.
    public nonisolated static func atomicWrite(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)
        // Replace existing file atomically.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    // MARK: - CRUD

    public func add(_ preset: Preset) {
        presets.append(preset)
        save()
    }

    public func update(_ preset: Preset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx] = preset
        save()
    }

    public func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    public func presets(for platform: Platform) -> [Preset] {
        presets.filter { $0.supports(platform) }
    }
}
