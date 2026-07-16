import XCTest
@testable import PhoneHubCore

final class AutomationStepExecutionTests: XCTestCase {
    private let id = UUID()

    func testMapsDeterministicSteps() throws {
        let cases: [(AutomationStep, String, [String: AnyCodableValue])] = [
            (.launchApp(id: id, name: "Settings"), "launch_app", ["app_name": .string("Settings")]),
            (.tap(id: id, label: "General", x: 1, y: 2), "tap", ["x": .double(1), "y": .double(2)]),
            (.doubleTap(id: id, label: nil, x: 3, y: 4), "double_tap", ["x": .double(3), "y": .double(4)]),
            (.longPress(id: id, label: nil, x: 5, y: 6, durationMs: 700), "long_press", ["x": .double(5), "y": .double(6), "duration_ms": .int(700)]),
            (.typeText(id: id, text: "hello"), "type_text", ["text": .string("hello")]),
            (.pressKey(id: id, key: "ENTER"), "press_key", ["key": .string("ENTER")]),
            (.swipe(id: id, direction: "up"), "swipe", ["direction": .string("up")]),
            (.pressHome(id: id), "press_home", [:]),
            (.pressBack(id: id), "press_back", [:]),
            (.pressAppSwitcher(id: id), "press_app_switcher", [:]),
            (.scrollTo(id: id, text: "Privacy", direction: "down"), "scroll_to", ["text": .string("Privacy"), "direction": .string("down")]),
            (.openURL(id: id, url: "https://example.com"), "open_url", ["url": .string("https://example.com")])
        ]
        for (step, tool, arguments) in cases {
            XCTAssertEqual(try toolInvocation(for: step, platform: .ios, serial: nil, binding: nil),
                           ToolInvocation(tool: tool, arguments: arguments))
        }
    }

    func testBindingOverridesRecordedPoint() throws {
        let invocation = try toolInvocation(for: .tap(id: id, label: "General", x: 1, y: 2),
                                            platform: .ios, serial: nil,
                                            binding: .init(x: 40, y: 50))
        XCTAssertEqual(invocation?.arguments, ["x": .double(40), "y": .double(50)])
    }

    func testLabelOnlyTapNeedsProbe() {
        XCTAssertThrowsError(try toolInvocation(for: .tap(id: id, label: "General", x: nil, y: nil),
                                                platform: .ios, serial: nil, binding: nil)) {
            XCTAssertEqual($0 as? AutomationStepExecutionError, .needsProbe)
        }
    }

    func testAndroidInjectsValidatedSerial() throws {
        let invocation = try XCTUnwrap(toolInvocation(for: .pressHome(id: id), platform: .android,
                                                      serial: "emulator-5554", binding: nil))
        XCTAssertEqual(invocation.arguments["serial"], .string("emulator-5554"))
        XCTAssertThrowsError(try toolInvocation(for: .pressHome(id: id), platform: .android,
                                                serial: "bad;serial", binding: nil))
    }

    func testRunnerOnlyStepsReturnNil() throws {
        XCTAssertNil(try toolInvocation(for: .wait(id: id, ms: 10), platform: .ios, serial: nil, binding: nil))
        XCTAssertNil(try toolInvocation(for: .aiStep(id: id, prompt: "help"), platform: .ios, serial: nil, binding: nil))
        XCTAssertNil(try toolInvocation(for: .switchDevice(id: id, deviceRef: "Pixel 8"),
                                        platform: .ios, serial: nil, binding: nil))
    }

    func testRecordedTapTextAndSwipeReachExecutionUnchanged() throws {
        var translator = HumanRecordingTranslator()
        let point = HumanRecordingPoint(
            windowPoint: CGPoint(x: 12, y: 34),
            devicePoint: CGPoint(x: 120, y: 340)
        )
        _ = translator.consume(.leftMouseDown(time: 0, point: point))
        _ = translator.consume(.leftMouseUp(time: 0.1, point: point))
        let tap = try XCTUnwrap(translator.consume(.idle(time: 0.5)).last)
        _ = translator.consume(.printableKey(time: 0.6, text: "hello"))
        let text = try XCTUnwrap(translator.consume(.returnKey(time: 0.7)).first)
        _ = translator.consume(.leftMouseDown(time: 0.8, point: point))
        let end = HumanRecordingPoint(
            windowPoint: CGPoint(x: 72, y: 34),
            devicePoint: CGPoint(x: 720, y: 340)
        )
        let swipe = try XCTUnwrap(translator.consume(.leftMouseUp(time: 0.9, point: end)).last)

        XCTAssertEqual(
            try toolInvocation(for: tap, platform: .ios, serial: nil, binding: nil),
            ToolInvocation(tool: "tap", arguments: ["x": .double(120), "y": .double(340)])
        )
        XCTAssertEqual(
            try toolInvocation(for: text, platform: .ios, serial: nil, binding: nil),
            ToolInvocation(tool: "type_text", arguments: ["text": .string("hello")])
        )
        XCTAssertEqual(
            try toolInvocation(for: swipe, platform: .ios, serial: nil, binding: nil),
            ToolInvocation(tool: "swipe", arguments: ["direction": .string("right")])
        )
    }
}
