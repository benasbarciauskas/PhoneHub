import XCTest
@testable import PhoneHubCore

final class TriggerTests: XCTestCase {

    // MARK: - Notification match

    func testMatchesNotificationPackageAndText() {
        let n = PhoneNotification(
            package: "com.whatsapp",
            title: "Alice",
            text: "Hello there",
            whenMs: 100
        )
        XCTAssertTrue(TriggerLogic.matchesNotification(
            n, packageContains: "whatsapp", textContains: "hello"
        ))
        XCTAssertTrue(TriggerLogic.matchesNotification(
            n, packageContains: "WHATS", textContains: nil
        ))
        XCTAssertFalse(TriggerLogic.matchesNotification(
            n, packageContains: "telegram", textContains: nil
        ))
        XCTAssertFalse(TriggerLogic.matchesNotification(
            n, packageContains: nil, textContains: "goodbye"
        ))
        // Empty filters match all.
        XCTAssertTrue(TriggerLogic.matchesNotification(
            n, packageContains: "", textContains: "  "
        ))
    }

    func testNotificationSeenKeyUsesPackageTitleWhen() {
        let a = PhoneNotification(package: "p", title: "t", text: "body1", whenMs: 42)
        let b = PhoneNotification(package: "p", title: "t", text: "body2", whenMs: 42)
        let c = PhoneNotification(package: "p", title: "t", text: "body1", whenMs: 99)
        XCTAssertEqual(TriggerLogic.notificationSeenKey(a), TriggerLogic.notificationSeenKey(b))
        XCTAssertNotEqual(TriggerLogic.notificationSeenKey(a), TriggerLogic.notificationSeenKey(c))
        XCTAssertEqual(TriggerLogic.notificationSeenKey(a), "p|t|42")
    }

    func testNewMatchingNotificationFiresOnce() {
        let n = PhoneNotification(package: "com.mail", title: "Invoice", text: "Pay", whenMs: 1)
        var seen = Set<String>()

        let first = TriggerLogic.newMatchingNotifications(
            current: [n], seen: seen,
            packageContains: "mail", textContains: nil
        )
        XCTAssertEqual(first.count, 1)
        // Consume into seen (fire path).
        for item in first { seen.insert(TriggerLogic.notificationSeenKey(item)) }

        let second = TriggerLogic.newMatchingNotifications(
            current: [n], seen: seen,
            packageContains: "mail", textContains: nil
        )
        XCTAssertTrue(second.isEmpty, "same notification must not re-fire")
    }

    func testNewMatchingIgnoresNonMatchingAndAlreadySeen() {
        let keep = PhoneNotification(package: "com.a", title: "X", text: "y", whenMs: 1)
        let noise = PhoneNotification(package: "com.b", title: "Z", text: "w", whenMs: 2)
        let seen = TriggerLogic.seedSeenKeys([keep])

        let news = TriggerLogic.newMatchingNotifications(
            current: [keep, noise],
            seen: seen,
            packageContains: "com",
            textContains: nil
        )
        // keep is seen; noise is new but package still matches "com" — should fire for noise only.
        XCTAssertEqual(news.map(\.package), ["com.b"])
    }

    func testSeedSeenPreventsFiringExistingNotifications() {
        let existing = PhoneNotification(package: "com.x", title: "Old", text: "msg", whenMs: 5)
        let seen = TriggerLogic.seedSeenKeys([existing])
        let news = TriggerLogic.newMatchingNotifications(
            current: [existing], seen: seen,
            packageContains: nil, textContains: nil
        )
        XCTAssertTrue(news.isEmpty)
    }

    // MARK: - Foreground edge

    func testForegroundEdgeFiresOncePerEnter() {
        let pkg = "com.instagram.android"
        // First observation: seed only.
        XCTAssertFalse(TriggerLogic.shouldFireForeground(
            previousPackage: nil,
            currentPackage: pkg,
            packageContains: "instagram",
            hasPriorObservation: false
        ))
        // Enter from elsewhere.
        XCTAssertTrue(TriggerLogic.shouldFireForeground(
            previousPackage: "com.android.launcher3",
            currentPackage: pkg,
            packageContains: "instagram",
            hasPriorObservation: true
        ))
        // Stay foreground: no re-fire.
        XCTAssertFalse(TriggerLogic.shouldFireForeground(
            previousPackage: pkg,
            currentPackage: pkg,
            packageContains: "instagram",
            hasPriorObservation: true
        ))
        // Leave then re-enter.
        XCTAssertFalse(TriggerLogic.shouldFireForeground(
            previousPackage: pkg,
            currentPackage: "com.android.chrome",
            packageContains: "instagram",
            hasPriorObservation: true
        ))
        XCTAssertTrue(TriggerLogic.shouldFireForeground(
            previousPackage: "com.android.chrome",
            currentPackage: pkg,
            packageContains: "instagram",
            hasPriorObservation: true
        ))
    }

    func testForegroundEmptyNeedleNeverFires() {
        XCTAssertFalse(TriggerLogic.shouldFireForeground(
            previousPackage: "a",
            currentPackage: "com.x",
            packageContains: "  ",
            hasPriorObservation: true
        ))
    }

    // MARK: - Foreground parser

    func testParseResumedActivity() {
        let dump = """
        ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)
          mResumedActivity: ActivityRecord{abc123 u0 com.whatsapp/.HomeActivity t12}
          mLastPausedActivity: ActivityRecord{def u0 com.android.launcher3/.Launcher t1}
        """
        XCTAssertEqual(ForegroundPackageParser.parse(dump), "com.whatsapp")
    }

    func testParseCurrentFocus() {
        let dump = """
        mCurrentFocus=Window{7a1b2c u0 com.spotify.music/com.spotify.music.MainActivity}
        mFocusedApp=AppWindowToken{x token=Token{y ActivityRecord{z u0 com.spotify.music/.MainActivity}}}
        """
        XCTAssertEqual(ForegroundPackageParser.parse(dump), "com.spotify.music")
    }

    func testParseTopResumedActivity() {
        let dump = "  topResumedActivity=ActivityRecord{aa u0 com.twitter.android/.StartActivity t9}"
        XCTAssertEqual(ForegroundPackageParser.parse(dump), "com.twitter.android")
    }

    func testParseEmptyReturnsNil() {
        XCTAssertNil(ForegroundPackageParser.parse(""))
        XCTAssertNil(ForegroundPackageParser.parse("no useful lines here"))
    }

    // MARK: - Store persistence

    @MainActor
    func testTriggerStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TriggerStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = TriggerStore(directory: dir)
        let id = UUID()
        let target = UUID()
        store.add(Trigger(
            id: id,
            name: "WA ping",
            enabled: true,
            deviceId: "serial1",
            deviceName: "Pixel",
            targetKind: .preset,
            targetId: target,
            condition: .notificationMatch(packageContains: "whatsapp", textContains: "ping")
        ))
        store.setEnabled(store.triggers[0], enabled: false)
        store.markFired(store.triggers[0], at: Date(timeIntervalSince1970: 1_700_000_000))

        let reloaded = TriggerStore(directory: dir)
        XCTAssertEqual(reloaded.triggers.count, 1)
        let t = reloaded.triggers[0]
        XCTAssertEqual(t.id, id)
        XCTAssertEqual(t.name, "WA ping")
        XCTAssertFalse(t.enabled)
        XCTAssertEqual(t.targetId, target)
        XCTAssertEqual(t.condition, .notificationMatch(packageContains: "whatsapp", textContains: "ping"))
        XCTAssertEqual(t.lastFired, Date(timeIntervalSince1970: 1_700_000_000))

        reloaded.delete(t)
        XCTAssertTrue(TriggerStore(directory: dir).triggers.isEmpty)
    }

    func testTriggerCodableAppForeground() throws {
        let t = Trigger(
            name: "IG",
            deviceId: "d",
            deviceName: "Phone",
            targetKind: .automation,
            targetId: UUID(),
            condition: .appForeground(packageContains: "instagram")
        )
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Trigger.self, from: data)
        XCTAssertEqual(decoded, t)
    }
}
