import XCTest
@testable import PhoneHubCore

final class KeychainStoreTests: XCTestCase {
    func testLiveRoundTripUsesIsolatedServiceWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["PHONEHUB_LIVE_KEYCHAIN_TEST"] == "1" else {
            throw XCTSkip("Set PHONEHUB_LIVE_KEYCHAIN_TEST=1 to run")
        }
        let service = "com.phonehub.llm.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: service)
        defer { try? store.deleteKey(provider: "openai") }

        XCTAssertNil(try store.key(provider: "openai"))
        try store.setKey(provider: "openai", key: "first-test-value")
        XCTAssertEqual(try store.key(provider: "openai"), "first-test-value")
        try store.setKey(provider: "openai", key: "updated-test-value")
        XCTAssertEqual(try store.key(provider: "openai"), "updated-test-value")
        try store.deleteKey(provider: "openai")
        XCTAssertNil(try store.key(provider: "openai"))
    }

    func testErrorDescriptionNeverContainsKeyMaterial() {
        let error = KeychainStoreError.unexpectedStatus(-1)
        XCTAssertFalse(error.localizedDescription.contains("secret-value"))
        XCTAssertEqual(error.localizedDescription, "Keychain operation failed (status -1).")
    }
}
