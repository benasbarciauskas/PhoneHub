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
}
