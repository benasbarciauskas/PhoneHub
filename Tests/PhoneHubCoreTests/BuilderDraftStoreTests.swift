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

    func testTimelineValidationAcceptsBoundEmptyFallbackAndValidActions() throws {
        let source = TextSource(name: "Captions", items: ["Hello"], mode: .static)
        let text = AutomationStep.typeText(id: UUID(), text: "")
        let draft = BuilderDraft(
            platform: .ios,
            steps: [text, .wait(id: UUID(), ms: 0), .aiStep(id: UUID(), prompt: "Dismiss popup")],
            textSourceBindings: [text.id: TextSourceRef(sourceID: source.id)]
        )

        XCTAssertNoThrow(try validateBuilderTimeline(draft, sources: [source]))
    }

    func testTimelineValidationRejectsEmptyAndInvalidEditableSteps() {
        XCTAssertThrowsError(try validateBuilderTimeline(BuilderDraft(), sources: [])) { error in
            XCTAssertEqual(error as? BuilderTimelineValidationError, .emptyTimeline)
        }
        let textID = UUID()
        XCTAssertThrowsError(try validateBuilderTimeline(
            BuilderDraft(platform: .ios, steps: [.typeText(id: textID, text: " \n")]),
            sources: []
        )) { error in
            XCTAssertEqual(error as? BuilderTimelineValidationError, .emptyTypeText(textID))
        }
        let aiID = UUID()
        XCTAssertThrowsError(try validateBuilderTimeline(
            BuilderDraft(platform: .ios, steps: [.aiStep(id: aiID, prompt: "")]),
            sources: []
        )) { error in
            XCTAssertEqual(error as? BuilderTimelineValidationError, .emptyAIAction(aiID))
        }
        let waitID = UUID()
        XCTAssertThrowsError(try validateBuilderTimeline(
            BuilderDraft(platform: .ios, steps: [.wait(id: waitID, ms: -1)]),
            sources: []
        )) { error in
            XCTAssertEqual(error as? BuilderTimelineValidationError, .invalidPause(waitID))
        }
    }

    func testTimelineValidationSurfacesMissingBoundSource() {
        let text = AutomationStep.typeText(id: UUID(), text: "fallback")
        let draft = BuilderDraft(
            platform: .android,
            steps: [text],
            textSourceBindings: [text.id: TextSourceRef(sourceID: UUID())]
        )
        XCTAssertThrowsError(try validateBuilderTimeline(draft, sources: [])) { error in
            guard case TextSourceResolutionError.missingSource = error else {
                return XCTFail("Expected missing source, got \(error)")
            }
        }
    }
}
