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
    }
}
