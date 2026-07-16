import XCTest
@testable import PhoneHubCore

final class BuilderDraftStoreTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("phonehub-builder-draft-test-\(UUID().uuidString)")
    }

    @MainActor
    func testAppendPinsPlatformAndPersistsStepsAndBinding() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BuilderDraftStore(directory: directory)
        let step = AutomationStep.typeText(id: UUID(), text: "fallback")
        let sourceID = UUID()

        try store.append(step, platform: .ios)
        store.setTextSource(sourceID, forStepID: step.id)

        let reopened = BuilderDraftStore(directory: directory)
        XCTAssertEqual(reopened.draft.platform, .ios)
        XCTAssertEqual(reopened.draft.steps, [step])
        XCTAssertEqual(
            reopened.draft.textSourceBindings[step.id],
            TextSourceRef(sourceID: sourceID)
        )
        XCTAssertThrowsError(try reopened.append(.pressBack(id: UUID()), platform: .android)) { error in
            XCTAssertEqual(error as? BuilderDraftError, .platformMismatch(expected: .ios))
        }
    }

    @MainActor
    func testMoveDeleteAndClearMaintainBindingsAndPlatform() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BuilderDraftStore(directory: directory)
        let first = AutomationStep.typeText(id: UUID(), text: "one")
        let second = AutomationStep.wait(id: UUID(), ms: 500)
        try store.append(first, platform: .android)
        try store.append(second, platform: .android)
        store.setTextSource(UUID(), forStepID: first.id)

        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(store.draft.steps.map(\.id), [second.id, first.id])
        store.delete(at: IndexSet(integer: 1))
        XCTAssertTrue(store.draft.textSourceBindings.isEmpty)
        XCTAssertEqual(store.draft.platform, .android)
        store.delete(at: IndexSet(integer: 0))
        XCTAssertNil(store.draft.platform)

        try store.append(first, platform: .ios)
        store.clear()
        XCTAssertEqual(store.draft, BuilderDraft())
    }

    @MainActor
    func testBuildAutomationCopiesParallelBindings() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BuilderDraftStore(directory: directory)
        let step = AutomationStep.typeText(id: UUID(), text: "fallback")
        let sourceID = UUID()
        try store.append(step, platform: .ios)
        store.setTextSource(sourceID, forStepID: step.id)

        let automation = try XCTUnwrap(store.automation(named: "Caption run"))
        XCTAssertEqual(automation.platform, .ios)
        XCTAssertEqual(automation.steps, [step])
        XCTAssertEqual(automation.textSourceBindings[step.id]?.sourceID, sourceID)
    }
}
