import XCTest
@testable import PhoneHubCore

@MainActor
final class RunHistoryStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func sampleRecord(
        name: String = "Open Instagram",
        kind: RunKind = .preset,
        deviceId: String = "device-1",
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> RunRecord {
        RunRecord(
            name: name,
            kind: kind,
            deviceId: deviceId,
            deviceName: "Pixel",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(12),
            outcome: .finished,
            log: ["Running…", "Done."]
        )
    }

    func testRoundTripAppendAndRecords() throws {
        let dir = try temporaryDirectory()
        let store = RunHistoryStore(directory: dir)
        let record = sampleRecord()

        store.append(record, deviceId: "device-1")

        let loaded = store.records(deviceId: "device-1")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], record)

        // Fresh store instance reloads from disk.
        let reopened = RunHistoryStore(directory: dir)
        XCTAssertEqual(reopened.records(deviceId: "device-1"), [record])
    }

    func testCapDropsOldestBeyondOneHundred() throws {
        let dir = try temporaryDirectory()
        let store = RunHistoryStore(directory: dir)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for i in 0..<105 {
            store.append(
                sampleRecord(name: "run-\(i)", startedAt: base.addingTimeInterval(TimeInterval(i))),
                deviceId: "dev"
            )
        }

        let records = store.records(deviceId: "dev")
        XCTAssertEqual(records.count, RunHistoryStore.maxRecordsPerDevice)
        // Newest first: last appended was run-104.
        XCTAssertEqual(records.first?.name, "run-104")
        XCTAssertEqual(records.last?.name, "run-5")
    }

    func testSanitizeDeviceIdMatchesChatStoreStyle() {
        XCTAssertEqual(RunHistoryStore.sanitizeDeviceId("abc-123"), "abc-123")
        XCTAssertEqual(RunHistoryStore.sanitizeDeviceId("a/b:c"), "a_b_c")
        XCTAssertEqual(RunHistoryStore.sanitizeDeviceId("../evil/../../x"), ".._evil_.._.._x")
    }

    func testUnsafeDeviceIDStaysInsideStoreDirectory() throws {
        let dir = try temporaryDirectory()
        let store = RunHistoryStore(directory: dir)
        store.append(sampleRecord(deviceId: "../evil/../../x"), deviceId: "../evil/../../x")

        let files = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        let root = dir.standardizedFileURL.path + "/"
        XCTAssertTrue(files[0].standardizedFileURL.path.hasPrefix(root))
        XCTAssertEqual(files[0].lastPathComponent, ".._evil_.._.._x.json")
    }

    func testRecordsNewestFirstAcrossKinds() throws {
        let dir = try temporaryDirectory()
        let store = RunHistoryStore(directory: dir)
        let older = sampleRecord(name: "old", kind: .preset,
                                 startedAt: Date(timeIntervalSince1970: 100))
        let newer = sampleRecord(name: "new", kind: .automation,
                                 startedAt: Date(timeIntervalSince1970: 200))
        store.append(older, deviceId: "d")
        store.append(newer, deviceId: "d")

        XCTAssertEqual(store.records(deviceId: "d").map(\.name), ["new", "old"])
    }

    func testEmptyDeviceReturnsEmpty() throws {
        let dir = try temporaryDirectory()
        let store = RunHistoryStore(directory: dir)
        XCTAssertTrue(store.records(deviceId: "missing").isEmpty)
    }
}
