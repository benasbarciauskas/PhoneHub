import XCTest
@testable import PhoneHub
import PhoneHubCore

@MainActor
final class AutomationEngineTests: XCTestCase {

    // The CLI rotates session_id on every `--resume`. `reply(_:)` must refuse to
    // spawn a resume without a captured (non-empty) id — otherwise it would
    // attach to the wrong or no conversation. This exercises that pure guard
    // without spawning a process.
    func testCanResumeRequiresNonEmptySessionId() {
        XCTAssertTrue(AutomationEngine.canResume(sessionId: "rotated-789"))
        XCTAssertFalse(AutomationEngine.canResume(sessionId: nil))
        XCTAssertFalse(AutomationEngine.canResume(sessionId: ""))
        XCTAssertFalse(AutomationEngine.canResume(sessionId: "   "))
    }

    func testLostSessionMessageIsUserFacing() {
        XCTAssertTrue(AutomationEngine.lostSessionMessage.contains("Lost session"))
        XCTAssertTrue(AutomationEngine.lostSessionMessage.lowercased().contains("start the goal again"))
    }
}
