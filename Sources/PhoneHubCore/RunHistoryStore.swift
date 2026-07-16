import Foundation
import Observation

/// Kind of run that produced a history record.
public enum RunKind: String, Codable, Equatable, Sendable {
    case preset
    case automation
}

/// Terminal outcome of a preset/automation run.
public enum RunOutcome: String, Codable, Equatable, Sendable {
    case finished
    case failed
    case stopped
}

/// One completed (or stopped/failed) preset/automation run, including its log.
public struct RunRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: RunKind
    public var deviceId: String
    public var deviceName: String
    public var startedAt: Date
    public var endedAt: Date
    public var outcome: RunOutcome
    public var log: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: RunKind,
        deviceId: String,
        deviceName: String,
        startedAt: Date,
        endedAt: Date = .now,
        outcome: RunOutcome,
        log: [String]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
        self.log = log
    }
}

/// Per-device run history under `Application Support/PhoneHub/history/<sanitizedId>.json`.
/// Cap: 100 runs per device (oldest dropped). Newest-first in memory after load.
@Observable
@MainActor
public final class RunHistoryStore {
    public static let maxRecordsPerDevice = 100

    private let directory: URL
    /// In-memory cache keyed by raw deviceId (not sanitized).
    private var cache: [String: [RunRecord]] = [:]

    /// - Parameter directory: override for tests; defaults to Application Support/PhoneHub/history.
    public init(directory: URL? = nil) {
        let dir = directory ?? PresetStore.defaultDirectory()
            .appendingPathComponent("history", isDirectory: true)
        self.directory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Append a completed run for `deviceId`. Newest first; drops oldest beyond the cap.
    public func append(_ record: RunRecord, deviceId: String) {
        var list = records(deviceId: deviceId)
        list.insert(record, at: 0)
        if list.count > Self.maxRecordsPerDevice {
            list = Array(list.prefix(Self.maxRecordsPerDevice))
        }
        cache[deviceId] = list
        save(list, deviceId: deviceId)
    }

    /// All records for the device, newest first.
    public func records(deviceId: String) -> [RunRecord] {
        if let cached = cache[deviceId] { return cached }
        let loaded = load(deviceId: deviceId)
        cache[deviceId] = loaded
        return loaded
    }

    /// Same sanitization as `ChatStore`: non `[A-Za-z0-9._-]` → `_`.
    public nonisolated static func sanitizeDeviceId(_ deviceId: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return deviceId.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
    }

    // MARK: - Persistence

    private func fileURL(for deviceId: String) -> URL {
        directory.appendingPathComponent("\(Self.sanitizeDeviceId(deviceId)).json", isDirectory: false)
    }

    private func load(deviceId: String) -> [RunRecord] {
        let url = fileURL(for: deviceId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        // Prefer newest-first arrays; tolerate oldest-first by sorting.
        if let decoded = try? JSONDecoder().decode([RunRecord].self, from: data) {
            return decoded.sorted { $0.startedAt > $1.startedAt }
        }
        return []
    }

    private func save(_ records: [RunRecord], deviceId: String) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try PresetStore.atomicWrite(data, to: fileURL(for: deviceId))
        } catch {
            // Non-fatal — keep in-memory list.
        }
    }
}
