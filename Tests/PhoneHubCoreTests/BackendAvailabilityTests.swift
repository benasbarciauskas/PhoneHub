import XCTest
@testable import PhoneHubCore

final class BackendAvailabilityTests: XCTestCase {
    func testResolverPathIsAvailable() {
        XCTAssertEqual(
            BackendAvailability.check(.claude, resolver: { name in "/tools/\(name)" }),
            .available(path: "/tools/claude")
        )
    }

    func testMissingClaudeHasExactHint() {
        XCTAssertEqual(
            BackendAvailability.check(.claude, resolver: { _ in nil }),
            .missing(hint: "Install the Claude CLI (https://claude.com/claude-code) and run `claude` once to log in. PhoneHub uses your own login — it stores no keys.")
        )
    }

    func testMissingCodexHasExactHint() {
        XCTAssertEqual(
            BackendAvailability.check(.codex, resolver: { _ in nil }),
            .missing(hint: "Install the Codex CLI (npm i -g @openai/codex) and run `codex` once to log in. PhoneHub uses your own login — it stores no keys.")
        )
    }
}
