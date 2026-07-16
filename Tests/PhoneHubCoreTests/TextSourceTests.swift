import XCTest
@testable import PhoneHubCore

final class TextSourceTests: XCTestCase {
    private let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let firstStepID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
    private let secondStepID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!

    func testCycleSourceResolvesOnceForEveryBoundStepAndPlansOneWrap() throws {
        let source = TextSource(
            id: sourceID,
            name: "Captions",
            items: ["first", "second"],
            cursor: 1,
            mode: .cycle
        )
        let steps: [AutomationStep] = [
            .typeText(id: firstStepID, text: "fallback one"),
            .wait(id: UUID(), ms: 100),
            .typeText(id: secondStepID, text: "fallback two"),
        ]
        let bindings = [
            firstStepID: TextSourceRef(sourceID: sourceID),
            secondStepID: TextSourceRef(sourceID: sourceID),
        ]

        let result = try resolveTextSourceBindings(
            steps: steps,
            bindings: bindings,
            sources: [source]
        )

        XCTAssertEqual(result.steps[0], .typeText(id: firstStepID, text: "second"))
        XCTAssertEqual(result.steps[2], .typeText(id: secondStepID, text: "second"))
        XCTAssertEqual(result.advances, [
            TextSourceAdvance(
                sourceID: sourceID,
                sourceName: "Captions",
                fromCursor: 1,
                toCursor: 0,
                wrapped: true
            )
        ])
    }

    func testStaticSourceUsesNormalizedCurrentItemAndDoesNotAdvance() throws {
        let source = TextSource(
            id: sourceID,
            name: "Signature",
            items: ["one", "two"],
            cursor: 5,
            mode: .static
        )

        let result = try resolveTextSourceBindings(
            steps: [.typeText(id: firstStepID, text: "literal")],
            bindings: [firstStepID: TextSourceRef(sourceID: sourceID)],
            sources: [source]
        )

        XCTAssertEqual(result.steps, [.typeText(id: firstStepID, text: "two")])
        XCTAssertTrue(result.advances.isEmpty)
    }

    func testUnboundLiteralRemainsUnchanged() throws {
        let step = AutomationStep.typeText(id: firstStepID, text: "literal")
        let result = try resolveTextSourceBindings(steps: [step], bindings: [:], sources: [])
        XCTAssertEqual(result.steps, [step])
        XCTAssertTrue(result.advances.isEmpty)
    }

    func testMissingAndEmptySourcesAreRejected() {
        XCTAssertThrowsError(try resolveTextSourceBindings(
            steps: [.typeText(id: firstStepID, text: "literal")],
            bindings: [firstStepID: TextSourceRef(sourceID: sourceID)],
            sources: []
        )) { error in
            XCTAssertEqual(error as? TextSourceResolutionError, .missingSource(sourceID))
        }

        let empty = TextSource(id: sourceID, name: "Empty", items: [], mode: .cycle)
        XCTAssertThrowsError(try resolveTextSourceBindings(
            steps: [.typeText(id: firstStepID, text: "literal")],
            bindings: [firstStepID: TextSourceRef(sourceID: sourceID)],
            sources: [empty]
        )) { error in
            XCTAssertEqual(error as? TextSourceResolutionError, .emptySource(sourceID))
        }
    }

    func testBindingOnNonTextStepIsRejected() {
        let source = TextSource(id: sourceID, name: "Source", items: ["one"], mode: .static)
        XCTAssertThrowsError(try resolveTextSourceBindings(
            steps: [.pressHome(id: firstStepID)],
            bindings: [firstStepID: TextSourceRef(sourceID: sourceID)],
            sources: [source]
        )) { error in
            XCTAssertEqual(error as? TextSourceResolutionError, .bindingRequiresTypeText(firstStepID))
        }
    }
}
