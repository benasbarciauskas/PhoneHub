import XCTest
@testable import PhoneHubCore

final class ChatTurnTests: XCTestCase {
    func testRetriesOnlyFirstFailedResumeTurn() {
        XCTAssertTrue(ChatTurn.shouldRetryAsFresh(
            exitCode: 1,
            isResumeTurn: true,
            alreadyRetried: false
        ))
        XCTAssertFalse(ChatTurn.shouldRetryAsFresh(
            exitCode: 0,
            isResumeTurn: true,
            alreadyRetried: false
        ))
        XCTAssertFalse(ChatTurn.shouldRetryAsFresh(
            exitCode: 1,
            isResumeTurn: false,
            alreadyRetried: false
        ))
        XCTAssertFalse(ChatTurn.shouldRetryAsFresh(
            exitCode: 1,
            isResumeTurn: true,
            alreadyRetried: true
        ))
    }

    func testBackendSwitchDropsSession() {
        XCTAssertNil(ChatTurn.sessionId(
            "existing-session",
            storedBackend: .claude,
            selectedBackend: .codex
        ))
        XCTAssertEqual(ChatTurn.sessionId(
            "existing-session",
            storedBackend: .codex,
            selectedBackend: .codex
        ), "existing-session")
    }
}
