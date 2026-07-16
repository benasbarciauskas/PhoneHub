# Human Recording Implementation Plan

> **For agentic workers:** Execute inline in this worktree. Do not delegate or invoke other AI CLIs. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture strictly scoped mirror-window input as live, editable Builder timeline steps.

**Architecture:** Put all event interpretation and coordinate conversion in `PhoneHubCore`; keep CGEvent, AX, permission, and lifecycle ownership in a focused app-target recorder. Connect emitted steps and the existing condense engine to a small Builder recording UI.

**Tech Stack:** Swift 5.9, SwiftUI, Observation, CoreGraphics, ApplicationServices, IOKit HID access, XCTest.

## Global Constraints

- Work only in `feat/human-recording`; commit on the current branch with Conventional Commits.
- TDD all pure logic and run the supplied build/test commands.
- Use a listen-only event tap and deterministically invalidate/remove it on every stop path.
- Reject out-of-scope events synchronously; never persist or log raw events.
- Keep source files under roughly 500 lines and add no provider implementation.

---

### Task 1: Pure translation and mapping

**Files:**
- Create: `Sources/PhoneHubCore/HumanRecording.swift`
- Create: `Tests/PhoneHubCoreTests/HumanRecordingTests.swift`
- Modify: `Sources/PhoneHubCore/AndroidController.swift`
- Modify: `Tests/PhoneHubCoreTests/AutomationStepExecutionTests.swift`

**Interfaces:**
- Produces `HumanRecordedEvent`, `HumanRecordingTranslator`, point mapping helpers,
  and `parseAndroidWindowManagerSize(_:)`.

- [ ] Write focused failing tests for click/double/long/drag/scroll/text/key/idle/wait behavior.
- [ ] Run the focused tests and confirm failures are missing symbols/behavior.
- [ ] Implement the smallest deterministic state machine and mapping helpers.
- [ ] Run focused tests green, then add and verify tap/type/swipe execution round trips.
- [ ] Commit as `feat: add human recording translation`.

### Task 2: Event tap, scoping, geometry, and permission

**Files:**
- Create: `Sources/PhoneHub/HumanRecorder.swift`
- Modify: `Sources/PhoneHub/WindowDock.swift`
- Modify: `Sources/PhoneHub/SystemPermissions.swift`
- Modify: `Sources/PhoneHub/LLMSettingsView.swift`

**Interfaces:**
- Consumes the Task 1 translator and device mapping.
- Produces `HumanRecorder.start(device:onSteps:)`, `stop()`, observable recording
  state/notices, and AX target-window geometry helpers.

- [ ] Expose minimal AX position/frame/focused-window helpers.
- [ ] Add Input Monitoring status/request/settings actions and its permission row.
- [ ] Implement target resolution for iPhone Mirroring and `PhoneHub-<serial>`.
- [ ] Install the listen-only tap and synchronously enforce frontmost/window scoping.
- [ ] Add batching, idle ticks, app/window termination observers, and deterministic teardown.
- [ ] Build and fix only concrete compiler errors; commit as `feat: capture scoped mirror input`.

### Task 3: Builder integration and description

**Files:**
- Modify: `Sources/PhoneHub/BuilderView.swift`
- Optionally create: `Sources/PhoneHub/BuilderRecordingView.swift`

**Interfaces:**
- Consumes `HumanRecorder`, `BuilderDraftStore.append`, and
  `AutomationEngine.condense(goal:rawSteps:backend:)`.

- [ ] Add Record/Stop toolbar state and the one-time plain-text password notice.
- [ ] Append emitted steps live using the focused platform.
- [ ] Stop on Builder disappearance and surface permission/recorder failures inline.
- [ ] Add a post-stop summary row and editable description populated through condense.
- [ ] Build and run focused tests; commit as `feat: record actions in builder`.

### Task 4: Review and release gates

**Files:** All changed files.

- [ ] Review the diff against every privacy, geometry, translation, lifecycle, and UI requirement.
- [ ] Fix all critical/important findings and re-review with a `Ready to merge` verdict.
- [ ] Run `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox`.
- [ ] Run `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`.
- [ ] Confirm clean status except intended commits and verify author/committer metadata.
