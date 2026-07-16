# Capture Permissions and Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add live macOS permission controls and enforce a persisted screen-capture policy across API, Claude, and Codex agent runs.

**Architecture:** One pure `PhoneHubCore` gate converts policy plus execution activity into an immutable decision. Plans carry that decision into CLI deny lists and API vision capture; app engines resolve persisted policy at run start and add one visible fallback notice. AppKit permission APIs remain in the app target.

**Tech Stack:** Swift 5.9, SwiftUI, Observation, AppKit, ApplicationServices, CoreGraphics, XCTest, SwiftPM.

## Global Constraints

- Work only in `feat/capture-permissions`.
- `duringRunsOnly` is the persisted default.
- When capture is denied, block `screenshot`, `start_recording`, and `stop_recording`.
- Text-only fallback uses `describe_screen` and is not a run failure.
- Poll permission state about every two seconds only while the settings sheet is open.
- TDD applies to pure logic.
- No new dependencies and no files over 500 lines.

---

### Task 1: Capture policy gate and persistence

**Files:**
- Create: `Sources/PhoneHubCore/ScreenCapturePolicy.swift`
- Create: `Tests/PhoneHubCoreTests/ScreenCapturePolicyTests.swift`
- Modify: `Sources/PhoneHubCore/LLMAppConfig.swift`
- Modify: `Tests/PhoneHubCoreTests/LLMAppConfigTests.swift`

**Interfaces:**
- Produces: `ScreenCapturePolicy`, `ScreenCaptureDecision`, and `screenCaptureDecision(policy:isRunActive:)`.
- Produces: `LLMAppConfig.screenCapturePolicy` with legacy fallback `.duringRunsOnly`.

- [ ] **Step 1: Write failing gate tests**

```swift
func testDuringRunsOnlyAllowsCaptureOnlyWhileActive() {
    XCTAssertTrue(screenCaptureDecision(policy: .duringRunsOnly, isRunActive: true).allowsCapture)
    XCTAssertFalse(screenCaptureDecision(policy: .duringRunsOnly, isRunActive: false).allowsCapture)
}

func testDisabledDeniesAllCaptureTools() {
    let decision = screenCaptureDecision(policy: .disabled, isRunActive: true)
    XCTAssertFalse(decision.allowsCapture)
    XCTAssertEqual(decision.deniedTools, ["screenshot", "start_recording", "stop_recording"])
}

func testAlwaysAllowsCaptureOutsideRuns() {
    XCTAssertTrue(screenCaptureDecision(policy: .always, isRunActive: false).allowsCapture)
}
```

- [ ] **Step 2: Run the focused tests and confirm missing-symbol failures**

Run: `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox --filter ScreenCapturePolicyTests`

Expected: compilation fails because the policy types do not exist.

- [ ] **Step 3: Implement the minimal pure gate**

```swift
public enum ScreenCapturePolicy: String, Codable, CaseIterable, Sendable {
    case duringRunsOnly, disabled, always
}

public struct ScreenCaptureDecision: Equatable, Sendable {
    public let allowsCapture: Bool
    public let deniedTools: [String]
    public let logMessage: String?
}

public func screenCaptureDecision(
    policy: ScreenCapturePolicy,
    isRunActive: Bool
) -> ScreenCaptureDecision
```

Use one switch to decide permission. Denied decisions always contain the three agreed tool names and a clear text-only fallback message.

- [ ] **Step 4: Add config tests, verify red, then persist the policy**

Add assertions that default is `.duringRunsOnly`, round-trip preserves `.always`, and legacy JSON without the field decodes to `.duringRunsOnly`. Run `swift test --disable-sandbox --filter LLMAppConfigTests` with the required environment, observe failures, then add the property, initializer default, CodingKey, and `decodeIfPresent` fallback.

- [ ] **Step 5: Run focused tests green and commit**

Run both focused suites with the required environment. Commit:

```bash
git add Sources/PhoneHubCore/ScreenCapturePolicy.swift Sources/PhoneHubCore/LLMAppConfig.swift Tests/PhoneHubCoreTests/ScreenCapturePolicyTests.swift Tests/PhoneHubCoreTests/LLMAppConfigTests.swift
git commit -m "feat: persist screen capture policy"
```

### Task 2: Enforce the decision in plans and API vision

**Files:**
- Modify: `Sources/PhoneHubCore/AutomationPlan.swift`
- Modify: `Sources/PhoneHubCore/ApiAgentRuntime.swift`
- Modify: `Sources/PhoneHubCore/LLMProviderFactory.swift`
- Modify: `Tests/PhoneHubCoreTests/AutomationPlanTests.swift`
- Modify: `Tests/PhoneHubCoreTests/ApiAgentRuntimeTests.swift`

**Interfaces:**
- Consumes: `ScreenCaptureDecision` from Task 1.
- Produces: `AutomationPlan.screenCaptureDecision`.
- Produces: Claude `--disallowedTools` and Codex `disabled_tools` configuration only for denied decisions.

- [ ] **Step 1: Write failing plan tests**

```swift
func testDisabledPolicyDeniesCaptureToolsForClaude() throws {
    let plan = try buildChatPlan(device: iosDevice, screenCapturePolicy: .disabled)
    let args = plan.arguments(mcpConfigPath: "/tmp/cfg.json")
    XCTAssertTrue(args.contains("--disallowedTools"))
    XCTAssertTrue(args.contains("mcp__mirroir__screenshot,mcp__mirroir__start_recording,mcp__mirroir__stop_recording"))
}

func testDisabledPolicyDeniesCaptureToolsForCodex() throws {
    let plan = try buildChatPlan(device: androidDevice, backend: .codex,
                                 screenCapturePolicy: .disabled)
    XCTAssertTrue(plan.arguments(mcpConfigPath: "/tmp/unused").contains(
        "mcp_servers.androir.disabled_tools=[\"screenshot\",\"start_recording\",\"stop_recording\"]"
    ))
}
```

Also assert active `.duringRunsOnly` and `.always` do not add deny arguments, while inactive `.duringRunsOnly` does.

- [ ] **Step 2: Run plan tests red**

Run the filtered `AutomationPlanTests` suite and confirm failures are caused by missing policy parameters/arguments.

- [ ] **Step 3: Carry the decision through plans**

Add `screenCaptureDecision` to `AutomationPlan`. Builders accept `screenCapturePolicy` and `isRunActive`, call the single gate, and append a text-only instruction to the preamble when denied. Claude arguments add one comma-separated `--disallowedTools` value; Codex configuration adds `disabled_tools` with raw MCP tool names.

- [ ] **Step 4: Write the failing API fallback test**

```swift
func testDeniedVisionUsesDescriptionWithoutScreenshot() async throws {
    let provider = CapturingProvider([
        LLMResponse(text: "Done.", toolCalls: [])
    ])
    let client = MapMCPClient(results: [
        "describe_screen": McpToolResult(
            text: #"- "Settings" button at (209, 100)"#, isError: false
        )
    ])
    let decision = screenCaptureDecision(policy: .disabled, isRunActive: true)
    let runtime = ApiAgentRuntime(provider: provider, client: client,
                                  vision: true, screenCaptureDecision: decision)
    _ = await runtime.run(
        systemPreamble: "system", prompt: "goal", priorMessages: [],
        maxToolCalls: 2, serverName: "mirroir", onEvent: { _ in }
    )
    XCTAssertEqual(client.calls.map(\.name), ["describe_screen"])
    XCTAssertTrue((await provider.firstMessages()).allSatisfy { $0.image == nil })
}
```

- [ ] **Step 5: Run API test red, implement text-only capture, then run green**

When vision is enabled, branch only on the plan decision inside the existing capture helper. The denied path calls `describe_screen` and builds `VisionCapture.userMessage(image: nil, describeText:)`. `makeConfiguredAPIRuntime` passes the plan decision.

- [ ] **Step 6: Run both focused suites and commit**

```bash
git add Sources/PhoneHubCore/AutomationPlan.swift Sources/PhoneHubCore/ApiAgentRuntime.swift Sources/PhoneHubCore/LLMProviderFactory.swift Tests/PhoneHubCoreTests/AutomationPlanTests.swift Tests/PhoneHubCoreTests/ApiAgentRuntimeTests.swift
git commit -m "feat: gate agent screen capture"
```

### Task 3: Resolve policy per run and expose settings model state

**Files:**
- Modify: `Sources/PhoneHub/AutomationEngine.swift`
- Modify: `Sources/PhoneHub/ChatEngine.swift`
- Modify: `Sources/PhoneHub/LLMSettingsModel.swift`
- Modify: `Tests/PhoneHubTests/AutomationEngineTests.swift`
- Modify: `Tests/PhoneHubTests/ChatEngineTests.swift`
- Modify: `Tests/PhoneHubTests/LLMSettingsModelTests.swift`

**Interfaces:**
- Consumes: policy-aware plan builders.
- Produces: injected `screenCapturePolicyProvider` closures for deterministic tests.
- Produces: `LLMSettingsModel.screenCapturePolicy` and `setScreenCapturePolicy(_:)`.

- [ ] **Step 1: Write failing model and engine-log tests**

The model test changes policy and confirms `LLMConfigStore.load()` returns it. Engine tests inject `.disabled`, launch through existing fake backends/runtimes, and assert the exact notice appears once in the run/chat log.

- [ ] **Step 2: Run the three focused suites red**

Use the required Swift test environment and confirm missing API or missing notice failures.

- [ ] **Step 3: Implement live policy resolution and one notice**

Each engine initializer gets a default provider closure:

```swift
screenCapturePolicyProvider: @escaping () -> ScreenCapturePolicy = {
    LLMConfigStore().load().screenCapturePolicy
}
```

Pass the value to plan construction with `isRunActive: true`. `AutomationEngine` appends the decision notice after its header; `ChatEngine` appends it as a system log after the user message and before starting. Retry/resume paths reuse the plan and do not append again.

- [ ] **Step 4: Run focused suites green and commit**

```bash
git add Sources/PhoneHub/AutomationEngine.swift Sources/PhoneHub/ChatEngine.swift Sources/PhoneHub/LLMSettingsModel.swift Tests/PhoneHubTests/AutomationEngineTests.swift Tests/PhoneHubTests/ChatEngineTests.swift Tests/PhoneHubTests/LLMSettingsModelTests.swift
git commit -m "feat: apply capture policy to active runs"
```

### Task 4: Add live permission controls and policy picker

**Files:**
- Create: `Sources/PhoneHub/SystemPermissions.swift`
- Modify: `Sources/PhoneHub/LLMSettingsView.swift`

**Interfaces:**
- Consumes: `LLMSettingsModel.screenCapturePolicy`.
- Produces: wrappers around `AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions`, `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, and exact System Settings URLs.

- [ ] **Step 1: Implement the focused system-permission wrapper**

```swift
enum SystemPermissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }
    static func requestAccessibility()
    static func requestScreenRecording()
    static func openAccessibilitySettings()
    static func openScreenRecordingSettings()
}
```

Use only the two supplied `x-apple.systempreferences:` URLs.

- [ ] **Step 2: Add the compact Permissions section**

Keep the existing settings layout in a `ScrollView`. Add status rows with green `checkmark.circle.fill` or red `xmark.circle.fill`, `Request…`, and `Open System Settings`. Add the exact Accessibility and Screen Recording explanatory copy. Add a three-option picker and the selected policy's one-line description.

- [ ] **Step 3: Add visible-only refresh behavior**

Refresh on appearance, `NSWindow.didBecomeKeyNotification`, and a cancellable two-second loop in `.task`. Because the task belongs to the sheet view, SwiftUI cancels it when the sheet closes.

- [ ] **Step 4: Build before commit and commit**

Run the required `swift build` command. Commit:

```bash
git add Sources/PhoneHub/SystemPermissions.swift Sources/PhoneHub/LLMSettingsView.swift
git commit -m "feat: add permissions settings pane"
```

### Task 5: Adversarial review and full verification

**Files:**
- Review all files changed since `origin/main`.

**Interfaces:**
- Produces: clean review verdict and fresh build/test evidence.

- [ ] **Step 1: Review requirements against the diff**

Check every capture path from `rg -n '"screenshot"|start_recording|stop_recording' Sources Tests`, legacy decoding, CLI initial/resume arguments, one-notice behavior, timer lifetime, deep links, exact copy, and file sizes. Record `Ready to merge: Yes / No / With fixes`.

- [ ] **Step 2: Fix findings with regression tests where applicable**

Any logic bug gets a failing test before its fix. Re-run the focused suite after each fix.

- [ ] **Step 3: Run full tests**

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
```

Expected: exit 0, zero failures.

- [ ] **Step 4: Run full build**

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

Expected: exit 0.

- [ ] **Step 5: Verify repository and commits**

Run `git diff --check`, `git status --short --branch`, `git log --oneline origin/main..HEAD`, and verify author/committer metadata contains only `Benas Barciauskas <benasbarciauskas@gmail.com>`. Commit any review-only corrections with a focused Conventional Commit message.
