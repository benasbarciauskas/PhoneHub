import XCTest
@testable import PhoneHubCore

final class SchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min; c.second = 0
        return calendar.date(from: c)!
    }

    private func intervalSchedule(minutes: Int, lastFired: Date? = nil) -> Schedule {
        Schedule(
            name: "Interval",
            targetKind: .preset,
            targetId: UUID(),
            deviceId: "d",
            deviceName: "Phone",
            cadence: .interval,
            intervalMinutes: minutes,
            lastFired: lastFired
        )
    }

    private func dailySchedule(hour: Int, minute: Int, lastFired: Date? = nil,
                               enabled: Bool = true) -> Schedule {
        Schedule(
            name: "Daily",
            targetKind: .automation,
            targetId: UUID(),
            deviceId: "d",
            deviceName: "Phone",
            cadence: .daily,
            hour: hour,
            minute: minute,
            enabled: enabled,
            lastFired: lastFired
        )
    }

    // MARK: - Interval nextFireDate

    func testIntervalNextFireDateAddsMinutesFromAfterWhenNeverFired() {
        let after = date(2026, 7, 16, 10, 0)
        let schedule = intervalSchedule(minutes: 15)
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 16, 10, 15))
    }

    func testIntervalNextFireDateUsesLastFiredPlusIntervalWhenLater() {
        let last = date(2026, 7, 16, 10, 0)
        let after = date(2026, 7, 16, 10, 5)
        let schedule = intervalSchedule(minutes: 30, lastFired: last)
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 16, 10, 30))
    }

    func testIntervalNextFireDateAdvancesFromAfterWhenLastFiredIsStale() {
        let last = date(2026, 7, 16, 8, 0)
        let after = date(2026, 7, 16, 12, 0)
        let schedule = intervalSchedule(minutes: 60, lastFired: last)
        // last+60m = 09:00, which is not > after → after + 60m
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 16, 13, 0))
    }

    func testIntervalMinutesClampedToAtLeastOne() {
        let after = date(2026, 7, 16, 10, 0)
        let schedule = intervalSchedule(minutes: 0)
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 16, 10, 1))
    }

    // MARK: - Interval isDue

    func testIntervalIsDueWhenNeverFired() {
        let schedule = intervalSchedule(minutes: 10)
        XCTAssertTrue(Scheduler.isDue(schedule, now: date(2026, 7, 16, 10, 0),
                                      lastFired: nil, calendar: calendar))
    }

    func testIntervalIsDueAfterElapsed() {
        let last = date(2026, 7, 16, 10, 0)
        let schedule = intervalSchedule(minutes: 10, lastFired: last)
        XCTAssertTrue(Scheduler.isDue(schedule, now: date(2026, 7, 16, 10, 10),
                                      lastFired: last, calendar: calendar))
        XCTAssertTrue(Scheduler.isDue(schedule, now: date(2026, 7, 16, 10, 11),
                                      lastFired: last, calendar: calendar))
    }

    func testIntervalNotDueBeforeElapsed() {
        let last = date(2026, 7, 16, 10, 0)
        let schedule = intervalSchedule(minutes: 10, lastFired: last)
        XCTAssertFalse(Scheduler.isDue(schedule, now: date(2026, 7, 16, 10, 9),
                                       lastFired: last, calendar: calendar))
    }

    func testDisabledNeverDue() {
        var schedule = intervalSchedule(minutes: 5)
        schedule.enabled = false
        XCTAssertFalse(Scheduler.isDue(schedule, now: date(2026, 7, 16, 10, 0),
                                       lastFired: nil, calendar: calendar))
    }

    // MARK: - Daily nextFireDate

    func testDailyNextFireDateSameDayWhenStillAhead() {
        let after = date(2026, 7, 16, 8, 0)
        let schedule = dailySchedule(hour: 9, minute: 30)
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 16, 9, 30))
    }

    func testDailyNextFireDateRollsToTomorrowAfterTodaysSlot() {
        let after = date(2026, 7, 16, 10, 0)
        let schedule = dailySchedule(hour: 9, minute: 0)
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 17, 9, 0))
    }

    func testDailyNextFireDateStrictlyAfterEqualMoment() {
        // exactly at fire time → next is tomorrow
        let after = date(2026, 7, 16, 9, 0)
        let schedule = dailySchedule(hour: 9, minute: 0)
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 17, 9, 0))
    }

    func testDailyMidnightRollover() {
        let after = date(2026, 7, 16, 23, 30)
        let schedule = dailySchedule(hour: 0, minute: 15)
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 17, 0, 15))
    }

    func testDailyMonthBoundaryRollover() {
        let after = date(2026, 7, 31, 20, 0)
        let schedule = dailySchedule(hour: 7, minute: 0)
        let next = Scheduler.nextFireDate(schedule, after: after, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 1, 7, 0))
    }

    // MARK: - Daily isDue

    func testDailyIsDueAfterFireTimeWhenNotYetFiredToday() {
        let schedule = dailySchedule(hour: 9, minute: 0)
        XCTAssertTrue(Scheduler.isDue(schedule, now: date(2026, 7, 16, 9, 0),
                                      lastFired: nil, calendar: calendar))
        XCTAssertTrue(Scheduler.isDue(schedule, now: date(2026, 7, 16, 9, 5),
                                      lastFired: date(2026, 7, 15, 9, 0),
                                      calendar: calendar))
    }

    func testDailyNotDueBeforeFireTime() {
        let schedule = dailySchedule(hour: 9, minute: 0)
        XCTAssertFalse(Scheduler.isDue(schedule, now: date(2026, 7, 16, 8, 59),
                                       lastFired: nil, calendar: calendar))
    }

    func testDailyNotDueWhenAlreadyFiredToday() {
        let todaysFire = date(2026, 7, 16, 9, 0)
        let schedule = dailySchedule(hour: 9, minute: 0, lastFired: todaysFire)
        XCTAssertFalse(Scheduler.isDue(schedule, now: date(2026, 7, 16, 15, 0),
                                       lastFired: todaysFire, calendar: calendar))
        // Fired slightly after the slot still counts.
        XCTAssertFalse(Scheduler.isDue(schedule, now: date(2026, 7, 16, 15, 0),
                                       lastFired: date(2026, 7, 16, 9, 1),
                                       calendar: calendar))
    }

    func testDailyDueAgainNextDay() {
        let yesterday = date(2026, 7, 15, 9, 0)
        let schedule = dailySchedule(hour: 9, minute: 0, lastFired: yesterday)
        XCTAssertTrue(Scheduler.isDue(schedule, now: date(2026, 7, 16, 9, 0),
                                      lastFired: yesterday, calendar: calendar))
    }

    func testDailyDisabledNeverDue() {
        let schedule = dailySchedule(hour: 9, minute: 0, enabled: false)
        XCTAssertFalse(Scheduler.isDue(schedule, now: date(2026, 7, 16, 10, 0),
                                       lastFired: nil, calendar: calendar))
    }

    // MARK: - ScheduleStore persistence

    @MainActor
    func testScheduleStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduleStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ScheduleStore(directory: dir)
        var schedule = dailySchedule(hour: 8, minute: 30)
        store.add(schedule)
        schedule.enabled = false
        store.update(schedule)
        store.markFired(schedule, at: date(2026, 7, 16, 8, 30))

        let reopened = ScheduleStore(directory: dir)
        XCTAssertEqual(reopened.schedules.count, 1)
        XCTAssertFalse(reopened.schedules[0].enabled)
        XCTAssertEqual(reopened.schedules[0].lastFired, date(2026, 7, 16, 8, 30))

        store.delete(schedule)
        XCTAssertTrue(store.schedules.isEmpty)
    }
}
