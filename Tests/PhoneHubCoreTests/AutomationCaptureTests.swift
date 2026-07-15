import XCTest
@testable import PhoneHubCore

final class AutomationCaptureTests: XCTestCase {
    func testDraftFiltersProbeToolsMapsCallsAndInsertsWaits() {
        let calls = [
            CapturedCall(tool: "describe_screen", rawInput: "{}"),
            CapturedCall(tool: "launch_app", rawInput: #"{"app_name":"Settings"}"#),
            CapturedCall(tool: "screenshot", rawInput: "{}"),
            CapturedCall(tool: "tap", rawInput: #"{"label":"General","x":209,"y":340}"#),
            CapturedCall(tool: "press_home", rawInput: "{}"),
            CapturedCall(tool: "list_apps", rawInput: "{}")
        ]
        let draft = automationDraft(from: calls, platform: .ios, name: "Settings flow",
                                    sourceGoal: "Open General")

        XCTAssertEqual(draft.name, "Settings flow")
        XCTAssertEqual(draft.platform, .ios)
        XCTAssertEqual(draft.sourceGoal, "Open General")
        XCTAssertFalse(draft.useCondensed)
        XCTAssertEqual(draft.steps.count, 5)
        XCTAssertEqual(draft.rawSteps, draft.steps)
        guard case .launchApp(_, "Settings") = draft.steps[0] else { return XCTFail("launch") }
        guard case .wait(_, 500) = draft.steps[1] else { return XCTFail("wait") }
        guard case let .tap(_, label, x, y) = draft.steps[2] else { return XCTFail("tap") }
        XCTAssertEqual(label, "General"); XCTAssertEqual(x, 209); XCTAssertEqual(y, 340)
        guard case .wait(_, 500) = draft.steps[3] else { return XCTFail("wait") }
        guard case .pressHome = draft.steps[4] else { return XCTFail("home") }
    }

    func testDraftMapsSupportedArgumentShapesAndIgnoresGarbage() {
        let calls = [
            CapturedCall(tool: "tap", rawInput: #"{"text":"Continue"}"#),
            CapturedCall(tool: "long_press", rawInput: #"{"x":10.5,"y":20,"duration_ms":900}"#),
            CapturedCall(tool: "type_text", rawInput: #"{"text":"hello"}"#),
            CapturedCall(tool: "unknown", rawInput: "not-json")
        ]
        let draft = automationDraft(from: calls, platform: .android, name: "A", sourceGoal: nil)
        let actions = draft.steps.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
        XCTAssertEqual(actions.count, 3)
        guard case let .tap(_, label, x, y) = actions[0] else { return XCTFail("tap") }
        XCTAssertEqual(label, "Continue"); XCTAssertNil(x); XCTAssertNil(y)
        guard case let .longPress(_, _, x2, y2, duration) = actions[1] else { return XCTFail("long") }
        XCTAssertEqual(x2, 10.5); XCTAssertEqual(y2, 20); XCTAssertEqual(duration, 900)
        guard case .typeText(_, "hello") = actions[2] else { return XCTFail("type") }
    }
}
