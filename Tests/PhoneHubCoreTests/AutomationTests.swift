import XCTest
@testable import PhoneHubCore

final class AutomationTests: XCTestCase {
    func testEveryStepRoundTripsWithStableType() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let steps: [(AutomationStep, String)] = [
            (.launchApp(id: id, name: "Settings"), "launchApp"),
            (.tap(id: id, label: "General", x: 1, y: 2), "tap"),
            (.doubleTap(id: id, label: nil, x: 3, y: 4), "doubleTap"),
            (.longPress(id: id, label: "Item", x: 5, y: 6, durationMs: 900), "longPress"),
            (.typeText(id: id, text: "hello"), "typeText"),
            (.pressKey(id: id, key: "ENTER"), "pressKey"),
            (.swipe(id: id, direction: "up"), "swipe"),
            (.pressHome(id: id), "pressHome"),
            (.pressBack(id: id), "pressBack"),
            (.pressAppSwitcher(id: id), "pressAppSwitcher"),
            (.scrollTo(id: id, text: "Privacy", direction: "down"), "scrollTo"),
            (.openURL(id: id, url: "https://example.com"), "openURL"),
            (.wait(id: id, ms: 500), "wait"),
            (.aiStep(id: id, prompt: "dismiss popup"), "aiStep"),
            (.switchDevice(id: id, deviceRef: "iPhone 15"), "switchDevice")
        ]

        for (step, expectedType) in steps {
            let data = try JSONEncoder().encode(step)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["type"] as? String, expectedType)
            XCTAssertEqual(try JSONDecoder().decode(AutomationStep.self, from: data), step)
            XCTAssertEqual(step.id, id)
        }
    }

    func testUnknownStepTypeThrows() {
        let json = #"{"type":"futureStep","id":"00000000-0000-0000-0000-000000000001"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(AutomationStep.self, from: Data(json.utf8)))
    }

    func testAutomationDefaults() {
        let automation = Automation(name: "Open settings", platform: .ios, steps: [])
        XCTAssertTrue(automation.useCondensed)
        XCTAssertEqual(automation.loop, .once)
        XCTAssertFalse(automation.sharedCoordinates)
        XCTAssertTrue(automation.bindings.isEmpty)
        XCTAssertTrue(automation.textSourceBindings.isEmpty)
        XCTAssertFalse(automation.pinned)
        XCTAssertNil(automation.rawSteps)
        XCTAssertNil(automation.sourceGoal)
        XCTAssertNil(automation.onSuccessCommand)
    }

    func testLegacyAutomationWithoutTextSourceBindingsStillDecodes() throws {
        let original = Automation(name: "Legacy", platform: .ios, steps: [])
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "textSourceBindings")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Automation.self, from: legacyData)

        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertTrue(decoded.textSourceBindings.isEmpty)
        XCTAssertNil(decoded.onSuccessCommand)
    }

    func testOnSuccessCommandRoundTrips() throws {
        let automation = Automation(
            name: "Post",
            platform: .ios,
            steps: [],
            onSuccessCommand: "buffer-mark-posted"
        )

        let data = try JSONEncoder().encode(automation)

        XCTAssertEqual(try JSONDecoder().decode(Automation.self, from: data), automation)
    }
}
