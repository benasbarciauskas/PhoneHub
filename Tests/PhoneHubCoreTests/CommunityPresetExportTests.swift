import XCTest
@testable import PhoneHubCore

final class CommunityPresetExportTests: XCTestCase {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testExportUsesStablePrettyPrintedOrderAndStripsPrivateFields() throws {
        let data = try communityPresetJSON(
            name: "Open Instagram",
            platform: .ios,
            app: "Instagram",
            steps: [
                .launchApp(id: id, name: "Instagram"),
                .tap(id: id, label: "Search", x: 120, y: 240),
            ]
        )

        XCTAssertEqual(String(decoding: data, as: UTF8.self), """
        {
          "name": "Open Instagram",
          "platform": "ios",
          "app": "Instagram",
          "steps": [
            {
              "type": "launchApp",
              "name": "Instagram"
            },
            {
              "type": "tap",
              "label": "Search"
            }
          ]
        }

        """)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"id\""))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"x\""))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"y\""))
    }

    func testEverySupportedAutomationStepMapsToCommunityFields() throws {
        let steps: [AutomationStep] = [
            .launchApp(id: id, name: "Settings"),
            .tap(id: id, label: "General", x: 1, y: 2),
            .doubleTap(id: id, label: "Photo", x: 3, y: 4),
            .longPress(id: id, label: "Item", x: 5, y: 6, durationMs: 900),
            .typeText(id: id, text: "hello"),
            .pressKey(id: id, key: "ENTER"),
            .swipe(id: id, direction: "up"),
            .pressHome(id: id),
            .pressBack(id: id),
            .pressAppSwitcher(id: id),
            .scrollTo(id: id, text: "Privacy", direction: "down"),
            .openURL(id: id, url: "https://example.com/path"),
            .wait(id: id, ms: 500),
            .aiStep(id: id, prompt: "Dismiss the popup"),
        ]

        let data = try communityPresetJSON(
            name: "All steps", platform: .android, app: "Settings", steps: steps
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let objects = try XCTUnwrap(root["steps"] as? [[String: Any]])

        XCTAssertEqual(objects.compactMap { $0["type"] as? String }, [
            "launchApp", "tap", "doubleTap", "longPress", "typeText", "pressKey",
            "swipe", "pressHome", "pressBack", "pressAppSwitcher", "scrollTo",
            "openURL", "wait", "aiStep",
        ])
        XCTAssertEqual(objects[3]["durationMs"] as? Int, 900)
        XCTAssertEqual(objects[4]["text"] as? String, "hello")
        XCTAssertEqual(objects[5]["key"] as? String, "ENTER")
        XCTAssertEqual(objects[6]["direction"] as? String, "up")
        XCTAssertEqual(objects[10]["text"] as? String, "Privacy")
        XCTAssertEqual(objects[10]["direction"] as? String, "down")
        XCTAssertEqual(objects[11]["url"] as? String, "https://example.com/path")
        XCTAssertEqual(objects[12]["ms"] as? Int, 500)
        XCTAssertEqual(objects[13]["prompt"] as? String, "Dismiss the popup")
        for object in objects {
            XCTAssertNil(object["id"])
            XCTAssertNil(object["x"])
            XCTAssertNil(object["y"])
        }
    }

    func testPointStepsRequireNonEmptyLabelsAndNameTheirIndex() {
        let invalid: [AutomationStep] = [
            .tap(id: id, label: nil, x: 10, y: 20),
            .doubleTap(id: id, label: "  ", x: nil, y: nil),
            .longPress(id: id, label: nil, x: 1, y: 2, durationMs: 500),
        ]

        for (expectedIndex, step) in invalid.enumerated() {
            let prefix = Array(repeating: AutomationStep.pressHome(id: id), count: expectedIndex)
            XCTAssertThrowsError(try communityPresetJSON(
                name: "Invalid", platform: .ios, app: "App", steps: prefix + [step]
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("index \(expectedIndex)"))
                XCTAssertTrue(error.localizedDescription.contains("non-empty label"))
            }
        }
    }

    func testSwitchDeviceIsRejectedWithItsIndex() {
        XCTAssertThrowsError(try communityPresetJSON(
            name: "Cross device",
            platform: .android,
            app: "App",
            steps: [.pressHome(id: id), .switchDevice(id: id, deviceRef: "Pixel")]
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("index 1"))
            XCTAssertTrue(error.localizedDescription.contains("switchDevice"))
            XCTAssertTrue(error.localizedDescription.contains("not shareable"))
        }
    }

    func testTopLevelFieldsAndStepsMustNotBeEmpty() {
        assertExportError(name: " ", app: "App", steps: [.pressHome(id: id)], contains: "name")
        assertExportError(name: "Preset", app: "\n", steps: [.pressHome(id: id)], contains: "App")
        assertExportError(name: "Preset", app: "App", steps: [], contains: "one step")
    }

    func testStepValuesMirrorCommunitySchemaRules() {
        let invalid: [(AutomationStep, String)] = [
            (.launchApp(id: id, name: " "), "app name"),
            (.pressKey(id: id, key: ""), "key"),
            (.swipe(id: id, direction: "diagonal"), "direction"),
            (.longPress(id: id, label: "Item", x: nil, y: nil, durationMs: -1), "duration"),
            (.scrollTo(id: id, text: " ", direction: "down"), "text"),
            (.scrollTo(id: id, text: "Privacy", direction: "forward"), "direction"),
            (.openURL(id: id, url: "not a URL"), "URL"),
            (.wait(id: id, ms: -1), "duration"),
            (.aiStep(id: id, prompt: "\t"), "prompt"),
        ]

        for (step, expectedMessage) in invalid {
            XCTAssertThrowsError(try communityPresetJSON(
                name: "Invalid", platform: .ios, app: "App", steps: [step]
            )) { error in
                XCTAssertTrue(
                    error.localizedDescription.localizedCaseInsensitiveContains(expectedMessage),
                    "Expected '\(error.localizedDescription)' to contain '\(expectedMessage)'"
                )
            }
        }

        XCTAssertNoThrow(try communityPresetJSON(
            name: "Clear field", platform: .ios, app: "App",
            steps: [.typeText(id: id, text: "")]
        ))
    }

    func testSlugLowercasesFoldsDiacriticsAndCollapsesSeparators() {
        XCTAssertEqual(slug("  Crème brûlée / 2026!!!  "), "creme-brulee-2026")
        XCTAssertEqual(slug("Hello___World"), "hello-world")
        XCTAssertEqual(slug("hello world"), slug("Hello___World"))
        XCTAssertEqual(slug("🔥"), "")
    }

    func testCommunityPathUsesPlatformAndSlugs() throws {
        XCTAssertEqual(
            try communityPresetPath(platform: .ios, app: "Instagram App", name: "Open Search!"),
            "presets/ios/instagram-app/open-search.json"
        )
        XCTAssertThrowsError(try communityPresetPath(platform: .android, app: "🔥", name: "Open"))
        XCTAssertThrowsError(try communityPresetPath(platform: .android, app: "App", name: "🔥"))
    }

    func testPresetExportsGoalAsSingleAIStep() throws {
        let preset = Preset(
            name: "Warm up TikTok",
            goal: "Scroll through five videos.",
            app: "TikTok",
            platforms: [.ios, .android]
        )

        let data = try communityPresetJSON(
            name: preset.name, platform: .android, app: "TikTok", preset: preset
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try XCTUnwrap(root["steps"] as? [[String: Any]])

        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0]["type"] as? String, "aiStep")
        XCTAssertEqual(steps[0]["prompt"] as? String, "Scroll through five videos.")
        XCTAssertNil(steps[0]["id"])
    }

    private func assertExportError(
        name: String,
        app: String,
        steps: [AutomationStep],
        contains expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try communityPresetJSON(name: name, platform: .ios, app: app, steps: steps),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains(expectedMessage),
                "Expected '\(error.localizedDescription)' to contain '\(expectedMessage)'",
                file: file,
                line: line
            )
        }
    }
}
