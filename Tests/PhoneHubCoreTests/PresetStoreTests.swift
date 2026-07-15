import XCTest
@testable import PhoneHubCore

final class PresetStoreTests: XCTestCase {

    func testEncodeDecodeRoundTrip() throws {
        let original = [
            Preset(name: "A", goal: "do a", app: "AppA", platforms: [.ios], maxSteps: 12),
            Preset(name: "B", goal: "do b", app: nil, platforms: [.ios, .android], maxSteps: 40)
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([Preset].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testExistingPresetJSONDecodesWithNoBackendOverride() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Old","goal":"g","platforms":["ios"],"maxSteps":40}
        """
        let preset = try JSONDecoder().decode(Preset.self, from: Data(json.utf8))
        XCTAssertNil(preset.backend)
    }

    func testDecodeTolerantSkipsBadEntries() {
        // Second entry is missing required fields (name/goal/platforms) → dropped.
        let json = """
        [
          {"id":"00000000-0000-0000-0000-000000000001","name":"Good","goal":"g","platforms":["ios"],"maxSteps":40},
          {"id":"oops","garbage":true},
          {"id":"00000000-0000-0000-0000-000000000002","name":"Good2","goal":"g2","platforms":["android"],"maxSteps":10}
        ]
        """
        let result = PresetStore.decodeTolerant(Data(json.utf8))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.name), ["Good", "Good2"])
    }

    func testDecodeTolerantOnGarbageReturnsEmpty() {
        XCTAssertTrue(PresetStore.decodeTolerant(Data("not json".utf8)).isEmpty)
    }

    func testAtomicWriteReplacesExistingFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("presets.json")

        try PresetStore.atomicWrite(Data("first".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first")

        try PresetStore.atomicWrite(Data("second".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second")

        // No stray temp files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(leftovers, ["presets.json"])
    }

    @MainActor
    func testSeedsBuiltInsOnFirstRunAndPersists() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PresetStore(directory: dir)
        XCTAssertEqual(store.presets.count, Preset.builtIns.count)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("presets.json").path))

        // A second store reads the same file (doesn't re-seed/duplicate).
        let reopened = PresetStore(directory: dir)
        XCTAssertEqual(reopened.presets.count, store.presets.count)
    }

    @MainActor
    func testCRUD() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PresetStore(directory: dir)
        let start = store.presets.count

        let p = Preset(name: "New", goal: "g", platforms: [.ios], maxSteps: 5)
        store.add(p)
        XCTAssertEqual(store.presets.count, start + 1)

        var edited = p; edited.name = "Renamed"
        store.update(edited)
        XCTAssertEqual(store.presets.first(where: { $0.id == p.id })?.name, "Renamed")

        store.delete(edited)
        XCTAssertEqual(store.presets.count, start)
    }

    @MainActor
    func testPresetsForPlatformFilter() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PresetStore(directory: dir)
        // Built-ins support both platforms.
        XCTAssertFalse(store.presets(for: .ios).isEmpty)
        XCTAssertFalse(store.presets(for: .android).isEmpty)
    }

    @MainActor
    func testDuplicateInsertsCopyAfterOriginalWithNewId() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PresetStore(directory: dir)
        let original = Preset(name: "Source", goal: "g", app: "App", platforms: [.ios], maxSteps: 9)
        store.add(original)
        let idx = store.presets.firstIndex(where: { $0.id == original.id })!

        let copy = store.duplicate(original)
        XCTAssertNotNil(copy)
        XCTAssertEqual(copy?.name, "Source copy")
        XCTAssertNotEqual(copy?.id, original.id)
        // Inserted right after the original.
        XCTAssertEqual(store.presets[idx + 1].id, copy?.id)
        // Other fields carried over.
        XCTAssertEqual(copy?.goal, "g")
        XCTAssertEqual(copy?.app, "App")
        XCTAssertEqual(copy?.maxSteps, 9)

        // Persisted: a reopened store sees the copy.
        let reopened = PresetStore(directory: dir)
        XCTAssertTrue(reopened.presets.contains { $0.name == "Source copy" })
    }

    @MainActor
    func testMoveReordersAndPersists() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PresetStore(directory: dir)
        // Start from a known set (ignore built-ins by clearing via delete).
        for existing in store.presets { store.delete(existing) }
        let a = Preset(name: "A", goal: "a", platforms: [.ios], maxSteps: 5)
        let b = Preset(name: "B", goal: "b", platforms: [.ios], maxSteps: 5)
        let c = Preset(name: "C", goal: "c", platforms: [.ios], maxSteps: 5)
        store.add(a); store.add(b); store.add(c)
        XCTAssertEqual(store.presets.map(\.name), ["A", "B", "C"])

        // Move A (index 0) to the end.
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(store.presets.map(\.name), ["B", "C", "A"])

        // Order persists across reopen.
        let reopened = PresetStore(directory: dir)
        XCTAssertEqual(reopened.presets.map(\.name), ["B", "C", "A"])
    }
}
