import Foundation
import Observation

/// How often a schedule should fire.
public enum ScheduleCadence: String, Codable, Equatable, Sendable {
    /// Every `intervalMinutes` minutes.
    case interval
    /// Once per day at local `hour`:`minute`.
    case daily
}

/// A saved schedule that runs a preset or automation on a device (app-open only).
public struct Schedule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Display label (usually the target preset/automation name).
    public var name: String
    public var targetKind: RunKind
    public var targetId: UUID
    public var deviceId: String
    public var deviceName: String
    public var cadence: ScheduleCadence
    /// Minutes between fires when `cadence == .interval`.
    public var intervalMinutes: Int
    /// Local hour 0…23 when `cadence == .daily`.
    public var hour: Int
    /// Local minute 0…59 when `cadence == .daily`.
    public var minute: Int
    public var enabled: Bool
    /// Last time this schedule successfully triggered a run (or a skip was recorded).
    public var lastFired: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        targetKind: RunKind,
        targetId: UUID,
        deviceId: String,
        deviceName: String,
        cadence: ScheduleCadence,
        intervalMinutes: Int = 60,
        hour: Int = 9,
        minute: Int = 0,
        enabled: Bool = true,
        lastFired: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.targetKind = targetKind
        self.targetId = targetId
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.cadence = cadence
        self.intervalMinutes = intervalMinutes
        self.hour = hour
        self.minute = minute
        self.enabled = enabled
        self.lastFired = lastFired
    }
}

/// Pure scheduling math (local timezone / calendar). Unit-testable without UI/timers.
public enum Scheduler {
    /// Next fire strictly after `after` for the schedule's cadence.
    /// - Interval: `after + intervalMinutes` (or lastFired + interval if that is later).
    /// - Daily: next occurrence of hour:minute local time strictly after `after`.
    public static func nextFireDate(
        _ schedule: Schedule,
        after: Date,
        calendar: Calendar = .current
    ) -> Date {
        switch schedule.cadence {
        case .interval:
            let minutes = max(1, schedule.intervalMinutes)
            let step = TimeInterval(minutes * 60)
            if let last = schedule.lastFired {
                let candidate = last.addingTimeInterval(step)
                if candidate > after { return candidate }
            }
            return after.addingTimeInterval(step)

        case .daily:
            let hour = min(23, max(0, schedule.hour))
            let minute = min(59, max(0, schedule.minute))
            var parts = calendar.dateComponents([.year, .month, .day], from: after)
            parts.hour = hour
            parts.minute = minute
            parts.second = 0
            parts.nanosecond = 0
            if let today = calendar.date(from: parts), today > after {
                return today
            }
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1,
                                                to: calendar.startOfDay(for: after))
                ?? after.addingTimeInterval(86_400)
            var tomorrowParts = calendar.dateComponents([.year, .month, .day], from: startOfTomorrow)
            tomorrowParts.hour = hour
            tomorrowParts.minute = minute
            tomorrowParts.second = 0
            tomorrowParts.nanosecond = 0
            return calendar.date(from: tomorrowParts)
                ?? startOfTomorrow.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
    }

    /// Whether the schedule should fire at `now`, given `lastFired`.
    /// Disabled schedules are never due. Uses local calendar for daily.
    public static func isDue(
        _ schedule: Schedule,
        now: Date,
        lastFired: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard schedule.enabled else { return false }

        switch schedule.cadence {
        case .interval:
            let minutes = max(1, schedule.intervalMinutes)
            let step = TimeInterval(minutes * 60)
            guard let last = lastFired else {
                // Never fired: due immediately when enabled (app may still skip if busy).
                return true
            }
            return now.timeIntervalSince(last) >= step

        case .daily:
            let hour = min(23, max(0, schedule.hour))
            let minute = min(59, max(0, schedule.minute))
            var parts = calendar.dateComponents([.year, .month, .day], from: now)
            parts.hour = hour
            parts.minute = minute
            parts.second = 0
            parts.nanosecond = 0
            guard let todaysFire = calendar.date(from: parts) else { return false }
            // Not yet reached today's fire time.
            guard now >= todaysFire else { return false }
            // Already fired for this day's slot.
            if let last = lastFired, last >= todaysFire { return false }
            return true
        }
    }
}

/// Loads/saves schedules to `Application Support/PhoneHub/schedules.json`.
@Observable
@MainActor
public final class ScheduleStore {
    public private(set) var schedules: [Schedule] = []

    private let fileURL: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? PresetStore.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("schedules.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Schedule].self, from: data) else {
            schedules = []
            return
        }
        schedules = decoded
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(schedules)
            try PresetStore.atomicWrite(data, to: fileURL)
        } catch {
            // Non-fatal.
        }
    }

    public func add(_ schedule: Schedule) {
        schedules.append(schedule)
        save()
    }

    public func update(_ schedule: Schedule) {
        guard let idx = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[idx] = schedule
        save()
    }

    public func delete(_ schedule: Schedule) {
        schedules.removeAll { $0.id == schedule.id }
        save()
    }

    public func setEnabled(_ schedule: Schedule, enabled: Bool) {
        guard let idx = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[idx].enabled = enabled
        save()
    }

    public func markFired(_ schedule: Schedule, at date: Date = .now) {
        guard let idx = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[idx].lastFired = date
        save()
    }
}
