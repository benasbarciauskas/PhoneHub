import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class LLMSettingsModelTests: XCTestCase {
    func testSelectionAndModelsPersistAsCodableConfig() throws {
        let suite = "LLMSettingsModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LLMConfigStore(defaults: defaults)
        let model = LLMSettingsModel(
            configStore: store,
            keyLookup: { _ in nil },
            keySetter: { _, _ in },
            keyDeleter: { _ in }
        )

        model.selectBackend(.openrouter)
        model.setModel("custom/router-model", for: .openrouter)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.selectedBackend, .openrouter)
        XCTAssertEqual(reloaded.model(forProvider: "openrouter"), "custom/router-model")
        let persisted = try XCTUnwrap(defaults.data(forKey: LLMConfigStore.storageKey))
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).lowercased().contains("key"))
    }

    func testKeyEntryIsWriteOnlyAndStatusTracksSaveDelete() {
        var storedValue: String?
        let model = LLMSettingsModel(
            configStore: LLMConfigStore(defaults: ephemeralDefaults()),
            keyLookup: { _ in storedValue },
            keySetter: { _, value in storedValue = value },
            keyDeleter: { _ in storedValue = nil }
        )
        model.selectBackend(.openai)

        XCTAssertEqual(model.keyStatus(for: .openai), "not set")
        XCTAssertTrue(model.saveKey("  fixture-credential  ", for: .openai))
        XCTAssertEqual(storedValue, "fixture-credential")
        XCTAssertEqual(model.keyStatus(for: .openai), "key saved ✓")
        model.clearKey(for: .openai)
        XCTAssertNil(storedValue)
        XCTAssertEqual(model.keyStatus(for: .openai), "not set")
    }

    func testKeyFailuresUseGenericStatusWithoutValue() {
        let model = LLMSettingsModel(
            configStore: LLMConfigStore(defaults: ephemeralDefaults()),
            keyLookup: { _ in throw KeychainStoreError.unexpectedStatus(-1) },
            keySetter: { _, _ in throw KeychainStoreError.unexpectedStatus(-1) },
            keyDeleter: { _ in throw KeychainStoreError.unexpectedStatus(-1) }
        )
        model.selectBackend(.anthropic)

        XCTAssertFalse(model.saveKey("fixture-credential", for: .anthropic))
        XCTAssertEqual(model.statusMessage, "Could not save the API key.")
        XCTAssertFalse(model.statusMessage?.contains("fixture-credential") ?? true)
    }

    func testVisionTogglePersistsInConfig() throws {
        let suite = "LLMSettingsModelTests.vision.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LLMConfigStore(defaults: defaults)
        let model = LLMSettingsModel(
            configStore: store,
            keyLookup: { _ in nil },
            keySetter: { _, _ in },
            keyDeleter: { _ in }
        )

        XCTAssertFalse(model.visionEnabled)
        model.setVision(true)
        XCTAssertTrue(model.visionEnabled)
        XCTAssertTrue(store.load().vision)
    }

    func testScreenDescriberModePersistsInConfig() throws {
        let suite = "LLMSettingsModelTests.describer.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LLMConfigStore(defaults: defaults)
        let model = LLMSettingsModel(
            configStore: store,
            keyLookup: { _ in nil },
            keySetter: { _, _ in },
            keyDeleter: { _ in }
        )

        XCTAssertEqual(model.screenDescriberMode, .auto)
        model.setScreenDescriberMode(.vision)
        XCTAssertEqual(model.screenDescriberMode, .vision)
        XCTAssertEqual(store.load().screenDescriberMode, .vision)
    }

    func testPreferKnownStepsTogglePersistsInConfig() throws {
        let suite = "LLMSettingsModelTests.preferKnown.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LLMConfigStore(defaults: defaults)
        let model = LLMSettingsModel(
            configStore: store,
            keyLookup: { _ in nil },
            keySetter: { _, _ in },
            keyDeleter: { _ in }
        )

        XCTAssertFalse(model.preferKnownSteps)
        model.setPreferKnownSteps(true)
        XCTAssertTrue(model.preferKnownSteps)
        XCTAssertTrue(store.load().preferKnownSteps)
        model.setPreferKnownSteps(false)
        XCTAssertFalse(store.load().preferKnownSteps)
    }

    func testScreenCapturePolicyPersistsInConfig() throws {
        let suite = "LLMSettingsModelTests.capturePolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LLMConfigStore(defaults: defaults)
        let model = LLMSettingsModel(
            configStore: store,
            keyLookup: { _ in nil },
            keySetter: { _, _ in },
            keyDeleter: { _ in }
        )

        XCTAssertEqual(model.screenCapturePolicy, .duringRunsOnly)
        model.setScreenCapturePolicy(.disabled)
        XCTAssertEqual(model.screenCapturePolicy, .disabled)
        XCTAssertEqual(store.load().screenCapturePolicy, .disabled)
    }

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LLMSettingsModelTests.\(UUID().uuidString)")!
    }
}
