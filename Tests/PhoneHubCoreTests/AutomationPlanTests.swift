import XCTest
@testable import PhoneHubCore

final class AutomationPlanTests: XCTestCase {

    private let iosDevice = Device(id: "00008110-AAAA", platform: .ios,
                                   model: "iPhone 15", osVersion: "26.0", status: "connected")
    private let androidDevice = Device(id: "ABC123XYZ", platform: .android,
                                       model: "Pixel 8", osVersion: "15", status: "device")

    func testClaudeArgumentsUnchangedByBackendField() throws {
        let preset = Preset(name: "p", goal: "g", platforms: [.ios], maxSteps: 10)
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        XCTAssertEqual(plan.backend, .claude)
        XCTAssertEqual(plan.arguments(mcpConfigPath: "/tmp/cfg.json"), [
            "-p", plan.prompt,
            "--append-system-prompt", plan.systemPreamble,
            "--output-format", "stream-json",
            "--verbose",
            "--mcp-config", "/tmp/cfg.json",
            "--allowedTools", "mcp__mirroir__*",
            "--max-turns", "10",
            "--permission-mode", "default"
        ])
    }

    func testBackendDefaultsToClaude() throws {
        let preset = Preset(name: "p", goal: "g", platforms: [.ios])
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        XCTAssertEqual(plan.backend, AgentBackend.claude)
    }

    func testIOSRoutesToMirroir() throws {
        let preset = Preset(name: "Open IG", goal: "open instagram",
                            platforms: [.ios], maxSteps: 25)
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        XCTAssertEqual(plan.serverName, "mirroir")
        XCTAssertEqual(plan.allowedTools, "mcp__mirroir__*")
        XCTAssertTrue(plan.mcpConfigJSON.contains("\"mirroir\""))
        XCTAssertTrue(plan.mcpConfigJSON.contains("mirroir-mcp"))
        XCTAssertTrue(plan.mcpConfigJSON.contains("npx"))
        XCTAssertEqual(plan.maxTurns, 25)
    }

    func testAndroidRoutesToAndroirWithSerial() throws {
        let preset = Preset(name: "Open IG", goal: "open instagram",
                            platforms: [.android], maxSteps: 30)
        let plan = try buildAutomationPlan(preset: preset, device: androidDevice)
        XCTAssertEqual(plan.serverName, "androir")
        XCTAssertEqual(plan.allowedTools, "mcp__androir__*")
        XCTAssertTrue(plan.mcpConfigJSON.contains("\"androir\""))
        XCTAssertTrue(plan.mcpConfigJSON.contains("androir-mcp"))
        XCTAssertTrue(plan.mcpConfigJSON.contains("\"npx\""))
        // Portable launch: no hardcoded local path / node entry point.
        XCTAssertFalse(plan.mcpConfigJSON.contains("/Volumes/"))
        XCTAssertFalse(plan.mcpConfigJSON.contains("dist/index.js"))
        // Serial is injected into the prompt so the agent passes it per-tool.
        XCTAssertTrue(plan.prompt.contains("ABC123XYZ"))
        XCTAssertEqual(plan.maxTurns, 30)
    }

    func testPlatformMismatchRefused() {
        let iosOnly = Preset(name: "iOS only", goal: "x", platforms: [.ios], maxSteps: 10)
        XCTAssertThrowsError(try buildAutomationPlan(preset: iosOnly, device: androidDevice)) {
            XCTAssertEqual($0 as? AutomationPlanError, .platformMismatch)
        }
    }

    func testInvalidAndroidSerialRefused() {
        let bad = Device(id: "bad serial!", platform: .android,
                         model: "x", osVersion: "1", status: "device")
        let preset = Preset(name: "p", goal: "g", platforms: [.android], maxSteps: 10)
        XCTAssertThrowsError(try buildAutomationPlan(preset: preset, device: bad)) {
            XCTAssertEqual($0 as? AutomationPlanError, .invalidSerial)
        }
    }

    func testMaxStepsMapsToMaxTurnsFlag() throws {
        let preset = Preset(name: "p", goal: "g", platforms: [.ios], maxSteps: 7)
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        let args = plan.arguments(mcpConfigPath: "/tmp/cfg.json")
        guard let idx = args.firstIndex(of: "--max-turns") else {
            return XCTFail("missing --max-turns")
        }
        XCTAssertEqual(args[idx + 1], "7")
    }

    func testArgumentsContainVerifiedFlags() throws {
        let preset = Preset(name: "p", goal: "g", platforms: [.ios], maxSteps: 10)
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        let args = plan.arguments(mcpConfigPath: "/tmp/cfg.json")
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("stream-json"))
        XCTAssertTrue(args.contains("--mcp-config"))
        XCTAssertTrue(args.contains("/tmp/cfg.json"))
        XCTAssertTrue(args.contains("--allowedTools"))
        XCTAssertTrue(args.contains("mcp__mirroir__*"))
        XCTAssertTrue(args.contains("--append-system-prompt"))
        // No blanket bypass of permissions on the claude spawn.
        XCTAssertFalse(args.contains("--dangerously-skip-permissions"))
    }

    func testSystemPreambleIsNeutralOperational() throws {
        let preset = Preset(name: "p", goal: "g", platforms: [.ios], maxSteps: 10)
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        let p = plan.systemPreamble.lowercased()
        XCTAssertTrue(p.contains("control a phone"))
        XCTAssertTrue(p.contains("achieve the goal"))
        // No evasion / anti-detection / personal-use framing.
        XCTAssertFalse(p.contains("detection"))
        XCTAssertFalse(p.contains("personal"))
        XCTAssertFalse(p.contains("evad"))
    }

    func testAppPrefixInjectedWhenSet() throws {
        let preset = Preset(name: "p", goal: "scroll", app: "TikTok",
                            platforms: [.ios], maxSteps: 10)
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        XCTAssertTrue(plan.prompt.contains("TikTok"))
    }

    func testPreambleContainsNeedInputInstruction() throws {
        let preset = Preset(name: "p", goal: "g", platforms: [.ios], maxSteps: 10)
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        XCTAssertTrue(plan.systemPreamble.contains("NEED_INPUT:"))
        let lower = plan.systemPreamble.lowercased()
        XCTAssertTrue(lower.contains("blocker"))
        XCTAssertTrue(lower.contains("do not guess"))
        XCTAssertTrue(lower.contains("resumed"))
    }

    func testResumeArgumentsReuseSameFlags() throws {
        let preset = Preset(name: "p", goal: "g", platforms: [.ios], maxSteps: 17)
        let plan = try buildAutomationPlan(preset: preset, device: iosDevice)
        let args = plan.resumeArguments(sessionId: "sess-42",
                                        reply: "use the work account",
                                        mcpConfigPath: "/tmp/cfg.json")
        // --resume <id> present.
        guard let rIdx = args.firstIndex(of: "--resume") else { return XCTFail("missing --resume") }
        XCTAssertEqual(args[rIdx + 1], "sess-42")
        // The reply is the -p prompt.
        guard let pIdx = args.firstIndex(of: "-p") else { return XCTFail("missing -p") }
        XCTAssertEqual(args[pIdx + 1], "use the work account")
        // Same mcp / tools / max-turns as the initial run.
        XCTAssertTrue(args.contains("--mcp-config"))
        XCTAssertTrue(args.contains("/tmp/cfg.json"))
        XCTAssertTrue(args.contains("--allowedTools"))
        XCTAssertTrue(args.contains("mcp__mirroir__*"))
        guard let mIdx = args.firstIndex(of: "--max-turns") else { return XCTFail("missing --max-turns") }
        XCTAssertEqual(args[mIdx + 1], "17")
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("stream-json"))
        XCTAssertTrue(args.contains("--append-system-prompt"))
        // No blanket bypass on resume either.
        XCTAssertFalse(args.contains("--dangerously-skip-permissions"))
    }

    func testResumeArgumentsMatchInitialMcpAndTools() throws {
        let preset = Preset(name: "p", goal: "g", platforms: [.android], maxSteps: 22)
        let plan = try buildAutomationPlan(preset: preset, device: androidDevice)
        let resume = plan.resumeArguments(sessionId: "s", reply: "r", mcpConfigPath: "/tmp/c.json")
        XCTAssertTrue(resume.contains("mcp__androir__*"))
        guard let mIdx = resume.firstIndex(of: "--max-turns") else { return XCTFail("missing --max-turns") }
        XCTAssertEqual(resume[mIdx + 1], "22")
    }
}
