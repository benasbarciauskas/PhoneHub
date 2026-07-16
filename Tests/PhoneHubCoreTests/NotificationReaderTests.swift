import XCTest
@testable import PhoneHubCore

final class NotificationReaderTests: XCTestCase {

    func testParseFixtureExtractsUsableNotifications() throws {
        let fixture = try loadFixture("dumpsys-notification-sample.txt")
        let notes = parseDumpsysNotifications(fixture)

        // Empty systemui title/text is skipped; 3 usable records remain.
        XCTAssertEqual(notes.count, 3)

        XCTAssertEqual(notes[0].package, "com.whatsapp")
        XCTAssertEqual(notes[0].title, "Alice")
        XCTAssertEqual(notes[0].text, "Hey, are you free later?")
        XCTAssertEqual(notes[0].whenMs, 1_712_345_678_901)

        XCTAssertEqual(notes[1].package, "com.google.android.gm")
        XCTAssertEqual(notes[1].title, "Invoice attached")
        XCTAssertEqual(notes[1].text, "Your receipt from PhoneHub is ready")
        XCTAssertEqual(notes[1].whenMs, 1_712_345_600_000)

        XCTAssertEqual(notes[2].package, "com.slack")
        XCTAssertEqual(notes[2].title, "Design review")
        XCTAssertEqual(notes[2].text, "Ben: shipping the notification hub panel today")
        XCTAssertEqual(notes[2].whenMs, 1_712_345_700_123)
    }

    func testParseEmptyReturnsEmpty() {
        XCTAssertEqual(parseDumpsysNotifications(""), [])
        XCTAssertEqual(parseDumpsysNotifications("\n\n"), [])
    }

    func testParseGarbageReturnsEmpty() {
        let garbage = """
        hello world
        not a dumpsys at all
        foo=bar
        """
        XCTAssertEqual(parseDumpsysNotifications(garbage), [])
    }

    func testParseSkipsRecordsWithoutPackage() {
        let dump = """
        NotificationRecord(0x1: missing pkg):
          extras={
              android.title=String (Orphan)
              android.text=String (No package field)
          }
          postTime=100
        """
        XCTAssertEqual(parseDumpsysNotifications(dump), [])
    }

    func testParseOpPkgFallback() {
        let dump = """
        NotificationRecord(0x2: op only):
          opPkg=com.example.app
          extras={
              android.title=String (Hi)
              android.text=String (Body)
          }
          when=42
        """
        let notes = parseDumpsysNotifications(dump)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].package, "com.example.app")
        XCTAssertEqual(notes[0].title, "Hi")
        XCTAssertEqual(notes[0].text, "Body")
        XCTAssertEqual(notes[0].whenMs, 42)
    }

    func testParseBigTextFallbackWhenTextMissing() {
        let dump = """
        NotificationRecord(0x3: bigText only):
          pkg=com.news.app
          extras={
              android.title=String (Headline)
              android.bigText=String (Long body only in bigText)
          }
          postTime=9
        """
        let notes = parseDumpsysNotifications(dump)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].text, "Long body only in bigText")
    }

    func testParseTitleOnlyIsKept() {
        let dump = """
        NotificationRecord(0x4: title only):
          pkg=com.clock
          extras={
              android.title=String (Alarm)
          }
          postTime=1
        """
        let notes = parseDumpsysNotifications(dump)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Alarm")
        XCTAssertEqual(notes[0].text, "")
    }

    // MARK: - Fixture loader

    private func loadFixture(_ name: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let url = testsDir.appendingPathComponent("Fixtures").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
