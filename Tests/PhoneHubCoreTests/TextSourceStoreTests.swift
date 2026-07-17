import XCTest
@testable import PhoneHubCore

final class TextSourceStoreTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-text-source-test-\(UUID().uuidString)")
    }

    @MainActor
    func testCRUDModeCursorAndPersistence() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TextSourceStore(directory: directory)

        var source = try store.add(name: "Captions", items: ["one", "two"], mode: .cycle)
        source.cursor = 1
        source.name = "Renamed"
        store.update(source)
        XCTAssertEqual(store.sources.first?.currentItem, "two")

        let reopened = TextSourceStore(directory: directory)
        XCTAssertEqual(reopened.sources.first?.name, "Renamed")
        XCTAssertEqual(reopened.sources.first?.cursor, 1)

        reopened.resetCursor(source.id)
        XCTAssertEqual(reopened.sources.first?.cursor, 0)
        reopened.delete(source.id)
        XCTAssertTrue(reopened.sources.isEmpty)
        XCTAssertTrue(TextSourceStore(directory: directory).sources.isEmpty)
    }

    @MainActor
    func testCommitAdvancesCycleOnceAndReportsWrap() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TextSourceStore(directory: directory)
        var source = try store.add(name: "Captions", items: ["one", "two"], mode: .cycle)
        source.cursor = 1
        store.update(source)
        let stepID = UUID()
        let automation = Automation(
            name: "Post",
            platform: .ios,
            steps: [.typeText(id: stepID, text: "fallback")],
            textSourceBindings: [stepID: TextSourceRef(sourceID: source.id)]
        )

        let resolution = try store.resolve(automation)
        XCTAssertEqual(resolution.steps, [.typeText(id: stepID, text: "two")])
        XCTAssertEqual(store.sources.first?.cursor, 1, "Resolution must not consume an item")

        XCTAssertEqual(store.commit(resolution), ["Text source “Captions” wrapped to the start."])
        XCTAssertEqual(store.sources.first?.cursor, 0)
    }

    @MainActor
    func testPreviewNeverAdvancesAndStoreRejectsInvalidSourceBoundaryInput() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TextSourceStore(directory: directory)
        let source = try store.add(name: "Static", items: ["value"], mode: .static)
        let stepID = UUID()
        let automation = Automation(
            name: "Preview",
            platform: .ios,
            steps: [.typeText(id: stepID, text: "fallback")],
            textSourceBindings: [stepID: TextSourceRef(sourceID: source.id)]
        )

        XCTAssertEqual(try store.currentSteps(for: automation), [
            .typeText(id: stepID, text: "value")
        ])
        XCTAssertEqual(store.sources.first?.cursor, 0)
        XCTAssertThrowsError(try store.add(name: " ", items: ["one"], mode: .static))
        XCTAssertThrowsError(try store.add(name: "Empty", items: [], mode: .static))
    }

    @MainActor
    func testRefreshReplacesItemsResetsCursorAndPersists() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TextSourceStore(directory: directory)
        var source = try store.add(name: "Captions", items: ["old", "stale"], mode: .cycle)
        source.cursor = 1
        source.refreshCommand = "next-captions"
        store.update(source)

        let count = try await store.refresh(source.id) { command, timeout in
            XCTAssertEqual(command, "next-captions")
            XCTAssertEqual(timeout, 30)
            return CommandResult(exitCode: 0, stdout: Data(#"["fresh", "new"]"#.utf8), stderr: "")
        }

        XCTAssertEqual(count, 2)
        XCTAssertEqual(store.sources.first?.items, ["fresh", "new"])
        XCTAssertEqual(store.sources.first?.cursor, 0)
        let reopened = TextSourceStore(directory: directory)
        XCTAssertEqual(reopened.sources.first?.items, ["fresh", "new"])
        XCTAssertEqual(reopened.sources.first?.cursor, 0)
    }
}
