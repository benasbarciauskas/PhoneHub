import Foundation
import Observation
import PhoneHubCore

@Observable
@MainActor
final class LLMSettingsModel {
    private(set) var config: LLMAppConfig
    private(set) var keyPresence: [String: Bool] = [:]
    private(set) var statusMessage: String?

    private let configStore: LLMConfigStore
    private let keyLookup: (String) throws -> String?
    private let keySetter: (String, String) throws -> Void
    private let keyDeleter: (String) throws -> Void

    init(
        configStore: LLMConfigStore = LLMConfigStore(),
        keyLookup: @escaping (String) throws -> String? = { try KeychainStore().key(provider: $0) },
        keySetter: @escaping (String, String) throws -> Void = {
            try KeychainStore().setKey(provider: $0, key: $1)
        },
        keyDeleter: @escaping (String) throws -> Void = {
            try KeychainStore().deleteKey(provider: $0)
        }
    ) {
        self.configStore = configStore
        self.keyLookup = keyLookup
        self.keySetter = keySetter
        self.keyDeleter = keyDeleter
        config = configStore.load()
        refreshKeyPresence()
    }

    var selectedBackend: AgentBackend { config.selectedBackend }
    var visionEnabled: Bool { config.vision }
    var screenDescriberMode: ScreenDescriberMode { config.screenDescriberMode }

    func selectBackend(_ backend: AgentBackend) {
        config.selectedBackend = backend
        persistConfig()
    }

    func model(for backend: AgentBackend) -> String {
        config.model(forProvider: backend.rawValue)
    }

    func setModel(_ model: String, for backend: AgentBackend) {
        guard backend.isAPI else { return }
        config.setModel(model, forProvider: backend.rawValue)
        persistConfig()
    }

    func setVision(_ enabled: Bool) {
        config.vision = enabled
        persistConfig()
    }

    func setScreenDescriberMode(_ mode: ScreenDescriberMode) {
        config.screenDescriberMode = mode
        persistConfig()
    }

    @discardableResult
    func saveKey(_ key: String, for backend: AgentBackend) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard backend.isAPI, !trimmed.isEmpty else { return false }
        do {
            try keySetter(backend.rawValue, trimmed)
            keyPresence[backend.rawValue] = true
            statusMessage = nil
            return true
        } catch {
            statusMessage = "Could not save the API key."
            return false
        }
    }

    func clearKey(for backend: AgentBackend) {
        guard backend.isAPI else { return }
        do {
            try keyDeleter(backend.rawValue)
            keyPresence[backend.rawValue] = false
            statusMessage = nil
        } catch {
            statusMessage = "Could not clear the API key."
        }
    }

    func keyStatus(for backend: AgentBackend) -> String {
        keyPresence[backend.rawValue] == true ? "key saved ✓" : "not set"
    }

    private func refreshKeyPresence() {
        for backend in AgentBackend.allCases where backend.isAPI {
            let value = (try? keyLookup(backend.rawValue)) ?? nil
            keyPresence[backend.rawValue] = !(value?.isEmpty ?? true)
        }
    }

    private func persistConfig() {
        do {
            try configStore.save(config)
            statusMessage = nil
        } catch {
            statusMessage = "Could not save LLM settings."
        }
    }
}
