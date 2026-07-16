import XCTest
@testable import PhoneHubCore

final class LLMAppConfigTests: XCTestCase {
    func testDefaultsContainProviderModelsAndClaudeSelection() {
        let config = LLMAppConfig.default

        XCTAssertEqual(config.selectedBackend, .claude)
        XCTAssertFalse(config.vision)
        XCTAssertEqual(config.screenDescriberMode, .auto)
        XCTAssertFalse(config.preferKnownSteps)
        XCTAssertEqual(config.model(forProvider: "openrouter"), "anthropic/claude-3.5-sonnet")
        XCTAssertEqual(config.model(forProvider: "openai"), "gpt-4.1")
        XCTAssertEqual(config.model(forProvider: "anthropic"), "claude-sonnet-4-20250514")
    }

    func testCodableRoundTripContainsNoSecretFields() throws {
        var config = LLMAppConfig.default
        config.selectedBackend = .codex
        config.setModel("custom/model", forProvider: "openrouter")
        config.vision = true
        config.screenDescriberMode = .vision
        config.preferKnownSteps = true

        let data = try JSONEncoder().encode(config)
        let json = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(json.contains("key"))
        XCTAssertFalse(json.contains("secret"))
        XCTAssertEqual(try JSONDecoder().decode(LLMAppConfig.self, from: data), config)
    }

    func testLegacyConfigWithoutVisionDecodesAsFalse() throws {
        let legacy = Data(#"{"selectedBackend":"openai","models":{"openai":"gpt-4.1"}}"#.utf8)
        let config = try JSONDecoder().decode(LLMAppConfig.self, from: legacy)
        XCTAssertEqual(config.selectedBackend, .openai)
        XCTAssertFalse(config.vision)
        XCTAssertEqual(config.screenDescriberMode, .auto)
        XCTAssertFalse(config.preferKnownSteps)
    }

    func testLegacyConfigWithoutPreferKnownStepsDecodesAsFalse() throws {
        let legacy = Data(#"{"selectedBackend":"claude","models":{},"vision":true,"screenDescriberMode":"ocr"}"#.utf8)
        let config = try JSONDecoder().decode(LLMAppConfig.self, from: legacy)
        XCTAssertFalse(config.preferKnownSteps)
        XCTAssertTrue(config.vision)
        XCTAssertEqual(config.screenDescriberMode, .ocr)
    }

    func testScreenDescriberModeRoundTrip() throws {
        var config = LLMAppConfig.default
        config.screenDescriberMode = .ocr
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(LLMAppConfig.self, from: data)
        XCTAssertEqual(decoded.screenDescriberMode, .ocr)
    }

    func testStoreMigratesLegacyBackendOnlyWhenNewConfigIsAbsent() throws {
        let suite = "LLMAppConfigTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AgentBackend.codex.rawValue, forKey: "agentBackend")
        let store = LLMConfigStore(defaults: defaults)

        XCTAssertEqual(store.load().selectedBackend, .codex)

        var saved = LLMAppConfig.default
        saved.selectedBackend = .claude
        saved.setModel("saved-model", forProvider: "openai")
        try store.save(saved)
        defaults.set(AgentBackend.codex.rawValue, forKey: "agentBackend")
        XCTAssertEqual(store.load(), saved)
    }

    func testUnknownOrBlankModelFallsBackToProviderDefault() {
        var config = LLMAppConfig(selectedBackend: .claude, models: [:])
        config.setModel("   ", forProvider: "openai")

        XCTAssertEqual(config.model(forProvider: "openai"), "gpt-4.1")
        XCTAssertEqual(config.model(forProvider: "unknown"), "")
    }
}
