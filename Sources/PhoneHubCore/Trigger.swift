import Foundation
import Observation

// MARK: - Condition

/// When an event trigger should fire (Android-only conditions).
public enum TriggerCondition: Codable, Equatable, Sendable {
    /// Fires when a **new** notification appears matching optional substrings.
    /// Empty/nil filters mean “any” for that field. Match is case-insensitive.
    case notificationMatch(packageContains: String?, textContains: String?)
    /// Fires when the named app **becomes** foreground (edge, not while staying).
    case appForeground(packageContains: String)
}

// MARK: - Model

/// A saved event trigger that runs a preset or automation when a phone event occurs.
/// App-open only (no launchd) — same lifetime as schedules.
public struct Trigger: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Display label (usually the target preset/automation name).
    public var name: String
    public var enabled: Bool
    public var deviceId: String
    public var deviceName: String
    public var targetKind: RunKind
    public var targetId: UUID
    public var condition: TriggerCondition
    /// Last time this trigger successfully fired or recorded a skip.
    public var lastFired: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        deviceId: String,
        deviceName: String,
        targetKind: RunKind,
        targetId: UUID,
        condition: TriggerCondition,
        lastFired: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.targetKind = targetKind
        self.targetId = targetId
        self.condition = condition
        self.lastFired = lastFired
    }
}

// MARK: - Pure evaluators (unit-testable)

/// Pure trigger matching / edge logic — no adb, no timers.
public enum TriggerLogic {

    /// Stable identity for a notification within the “seen once” set.
    /// Uses package + title + whenMs (not body text) so the same post is unique.
    public static func notificationSeenKey(_ n: PhoneNotification) -> String {
        let when = n.whenMs.map(String.init) ?? ""
        return "\(n.package)|\(n.title)|\(when)"
    }

    /// Case-insensitive substring; empty/nil needle matches everything.
    public static func containsCI(_ haystack: String, _ needle: String?) -> Bool {
        guard let needle, !needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return haystack.range(of: needle, options: .caseInsensitive) != nil
    }

    /// Whether a notification matches the filter (package and/or title/text).
    public static func matchesNotification(
        _ n: PhoneNotification,
        packageContains: String?,
        textContains: String?
    ) -> Bool {
        guard containsCI(n.package, packageContains) else { return false }
        // textContains matches title or body.
        guard let textContains, !textContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return containsCI(n.title, textContains) || containsCI(n.text, textContains)
    }

    /// Notifications that are matching **and** not yet in `seen`.
    /// Does not mutate; caller merges keys into seen after handling (fire or skip).
    public static func newMatchingNotifications(
        current: [PhoneNotification],
        seen: Set<String>,
        packageContains: String?,
        textContains: String?
    ) -> [PhoneNotification] {
        current.filter { n in
            let key = notificationSeenKey(n)
            guard !seen.contains(key) else { return false }
            return matchesNotification(n, packageContains: packageContains, textContains: textContains)
        }
    }

    /// Keys to seed a seen-set from the current dump (first poll: no fire for existing notifs).
    public static func seedSeenKeys(_ current: [PhoneNotification]) -> Set<String> {
        Set(current.map(notificationSeenKey))
    }

    /// Edge-trigger: fire when package **becomes** a match (was not matching, now is).
    /// First observation should pass `previousPackage` as `nil` with `hasPriorObservation: false`
    /// so the initial foreground state does not fire.
    public static func shouldFireForeground(
        previousPackage: String?,
        currentPackage: String?,
        packageContains: String,
        hasPriorObservation: Bool
    ) -> Bool {
        guard hasPriorObservation else { return false }
        let needle = packageContains.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        let wasMatch = previousPackage.map { containsCI($0, needle) } ?? false
        let isMatch = currentPackage.map { containsCI($0, needle) } ?? false
        return isMatch && !wasMatch
    }
}

// MARK: - Foreground package parser / reader

/// Parse foreground package from dumpsys activity / window text.
public enum ForegroundPackageParser {

    /// Extract the resumed/focused app package from dumpsys output.
    /// Handles common forms:
    /// - `mResumedActivity: ActivityRecord{… u0 com.pkg/.Activity …}`
    /// - `mCurrentFocus=Window{… com.pkg/com.pkg.Activity}`
    /// - `topResumedActivity=ActivityRecord{… com.pkg/.Main …}`
    public static func parse(_ dumpsys: String) -> String? {
        guard !dumpsys.isEmpty else { return nil }

        // Prefer explicit resumed-activity lines (most reliable for "foreground").
        // Package is the component before `/` in `pkg/.Activity` or `pkg/pkg.Activity`.
        let linePrefixes = [
            "mResumedActivity",
            "topResumedActivity",
            "mCurrentFocus",
            "mFocusedApp",
        ]
        for line in dumpsys.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard linePrefixes.contains(where: { s.contains($0) }) else { continue }
            if let pkg = packageBeforeSlash(in: s), isPlausiblePackage(pkg) {
                return pkg
            }
        }
        return nil
    }

    /// First `com.foo.bar/`-style token on the line.
    private static func packageBeforeSlash(in line: String) -> String? {
        // Require a dotted package (at least one `.`) immediately before `/`.
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+)/"#
        ) else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 2,
              match.range(at: 1).location != NSNotFound else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    private static func isPlausiblePackage(_ s: String) -> Bool {
        guard s.contains("."), s.count >= 3, s.count <= 200 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// Read the current foreground package via adb dumpsys (Android).
public enum ForegroundReader {

    /// Best-effort foreground package for `serial`. Nil on bad serial / tool failure / parse miss.
    public static func fetch(serial: String) -> String? {
        guard isValidSerial(serial) else { return nil }

        // activities dump usually has mResumedActivity / topResumedActivity.
        if let text = dumpsys(serial, "activity", "activities"),
           let pkg = ForegroundPackageParser.parse(text) {
            return pkg
        }
        // Fallback: window focus line.
        if let text = dumpsys(serial, "window", "windows"),
           let pkg = ForegroundPackageParser.parse(text) {
            return pkg
        }
        if let text = dumpsys(serial, "window"),
           let pkg = ForegroundPackageParser.parse(text) {
            return pkg
        }
        return nil
    }

    private static func dumpsys(_ serial: String, _ args: String...) -> String? {
        var full = ["shell", "dumpsys"]
        full.append(contentsOf: args)
        guard let res = try? runTool(
            "adb",
            ["-s", serial] + full,
            timeout: 12
        ), res.exitCode == 0,
           let text = String(data: res.stdout, encoding: .utf8),
           !text.isEmpty else {
            return nil
        }
        return text
    }
}

// MARK: - Store

/// Loads/saves triggers to `Application Support/PhoneHub/triggers.json`.
@Observable
@MainActor
public final class TriggerStore {
    public private(set) var triggers: [Trigger] = []

    private let fileURL: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? PresetStore.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("triggers.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Trigger].self, from: data) else {
            triggers = []
            return
        }
        triggers = decoded
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(triggers)
            try PresetStore.atomicWrite(data, to: fileURL)
        } catch {
            // Non-fatal.
        }
    }

    public func add(_ trigger: Trigger) {
        triggers.append(trigger)
        save()
    }

    public func update(_ trigger: Trigger) {
        guard let idx = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        triggers[idx] = trigger
        save()
    }

    public func delete(_ trigger: Trigger) {
        triggers.removeAll { $0.id == trigger.id }
        save()
    }

    public func setEnabled(_ trigger: Trigger, enabled: Bool) {
        guard let idx = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        triggers[idx].enabled = enabled
        save()
    }

    public func markFired(_ trigger: Trigger, at date: Date = .now) {
        guard let idx = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        triggers[idx].lastFired = date
        save()
    }
}
