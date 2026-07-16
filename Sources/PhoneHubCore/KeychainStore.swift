import Foundation
import Security

public enum KeychainStoreError: Error, LocalizedError, Equatable {
    case invalidValue
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidValue:
            return "Keychain returned an invalid value."
        case .unexpectedStatus(let status):
            return "Keychain operation failed (status \(status))."
        }
    }
}

public struct KeychainStore: Sendable {
    public static let defaultService = "com.phonehub.llm"

    private let service: String

    public init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    public func setKey(provider: String, key: String) throws {
        let value = Data(key.utf8)
        let query = baseQuery(provider: provider)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: value] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = value
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    public func key(provider: String) throws -> String? {
        var query = baseQuery(provider: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidValue
        }
        return value
    }

    public func deleteKey(provider: String) throws {
        let status = SecItemDelete(baseQuery(provider: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(provider: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
    }
}
