import XCTest
@testable import PhoneHubCore

final class AutomationStoreTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-automation-test-\(UUID().uuidString)")
    }

    @MainActor
    func testCRUDDuplicateFilterAndPersistence() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AutomationStore(directory: dir)
        XCTAssertTrue(store.automations.isEmpty)

        let ios = Automation(name: "iOS", platform: .ios, steps: [.pressHome(id: UUID())])
        let android = Automation(name: "Android", platform: .android, steps: [.pressBack(id: UUID())])
        store.add(ios)
        store.add(android)
        XCTAssertEqual(store.automations(for: .ios).map(\.id), [ios.id])
        XCTAssertEqual(store.automations(for: .android).map(\.id), [android.id])

        var edited = ios
        edited.name = "Renamed"
        store.update(edited)
        XCTAssertEqual(store.automations.first(where: { $0.id == ios.id })?.name, "Renamed")

        let copy = try XCTUnwrap(store.duplicate(edited))
        XCTAssertEqual(copy.name, "Renamed copy")
        XCTAssertNotEqual(copy.id, edited.id)
        XCTAssertEqual(store.automations.firstIndex(where: { $0.id == copy.id }),
                       store.automations.firstIndex(where: { $0.id == edited.id })! + 1)

        store.delete(android)
        XCTAssertFalse(store.automations.contains(where: { $0.id == android.id }))

        let reopened = AutomationStore(directory: dir)
        XCTAssertEqual(reopened.automations, store.automations)
    }

    @MainActor
    func testCorruptFileLoadsEmpty() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("automations.json"))
        XCTAssertTrue(AutomationStore(directory: dir).automations.isEmpty)
    }
}
