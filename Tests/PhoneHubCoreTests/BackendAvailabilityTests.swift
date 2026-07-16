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

    func testAPIBackendIsAvailableOnlyWithNonEmptyKey() {
        XCTAssertEqual(
            BackendAvailability.check(.openai, resolver: { _ in nil }, keyLookup: { _ in "key" }),
            .available(path: "api")
        )
        XCTAssertEqual(
            BackendAvailability.check(.openai, resolver: { _ in "/must/not/be/used" },
                                      keyLookup: { _ in "  " }),
            .missing(hint: "Add your OpenAI API key in Settings.")
        )
    }

    func testEachMissingAPIBackendHasProviderSpecificHint() {
        let expected: [(AgentBackend, String)] = [
            (.openrouter, "Add your OpenRouter API key in Settings."),
            (.openai, "Add your OpenAI API key in Settings."),
            (.anthropic, "Add your Anthropic API key in Settings.")
        ]
        for (backend, hint) in expected {
            XCTAssertEqual(
                BackendAvailability.check(backend, resolver: { _ in nil }, keyLookup: { _ in nil }),
                .missing(hint: hint)
            )
        }
    }

    func testAPIAvailabilityUsesKeyLookupWithoutExposingValue() {
        for backend in [AgentBackend.openrouter, .openai, .anthropic] {
            XCTAssertEqual(
                BackendAvailability.check(
                    backend,
                    resolver: { _ in XCTFail("API backend must not resolve a binary"); return nil },
                    keyLookup: { provider in provider == backend.rawValue ? "fixture-value" : nil }
                ),
                .available(path: "api")
            )
        }
    }
}
