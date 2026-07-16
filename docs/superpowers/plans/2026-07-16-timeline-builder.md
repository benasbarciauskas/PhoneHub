# Interactive Action Timeline Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace PhoneHub's one-off command box with a persistent action timeline builder, manual screenshot tap picker, and cycling imported text sources.

**Architecture:** Pure Core types own parsing, coordinate conversion, draft persistence, source binding, and run-time substitution. The existing agent engine gains a constrained builder plan, while the existing automation runner resolves source bindings before execution and advances cursors only on success. Focused SwiftUI files provide builder, timeline-row, tap-picker, and text-source management views.

**Tech Stack:** Swift 5.9, SwiftUI on macOS 14, Observation, Foundation JSON/XML parsing, XCTest, direct MCP stdio clients.

## Global Constraints

- Work only in `feat/timeline-builder`; do not modify another checkout.
- Preserve `AutomationStep` Codable compatibility and old automation JSON.
- Parse files defensively: 1 MB, valid UTF-8, 10,000 items, no XML external entities.
- TDD all pure logic and keep production/view files below roughly 500 lines.
- Use argument arrays for processes; never form shell command strings.
- Verify with the exact requested build and full-test commands.

---

### Task 1: Coordinate mapping and mirroir status parsing

**Files:**
- Create: `Sources/PhoneHubCore/TapCoordinateMapping.swift`
- Create: `Tests/PhoneHubCoreTests/TapCoordinateMappingTests.swift`

**Interfaces:**
- Produces: `mapClickToDevicePoint(clickInView:viewSize:imagePixelSize:deviceSpaceSize:) -> CGPoint`
- Produces: `parseMirroirWindowSize(_:) -> CGSize?`

- [ ] **Step 1: Write failing mapping and status tests**

```swift
XCTAssertEqual(
    mapClickToDevicePoint(
        clickInView: CGPoint(x: 150, y: 250),
        viewSize: CGSize(width: 300, height: 500),
        imagePixelSize: CGSize(width: 820, height: 1796),
        deviceSpaceSize: CGSize(width: 410, height: 898)
    ),
    CGPoint(x: 205, y: 449), accuracy: 0.001
)
XCTAssertEqual(
    parseMirroirWindowSize("Connected — mirroring active (window: 410x898, pos=(1,2), portrait)"),
    CGSize(width: 410, height: 898)
)
```

- [ ] **Step 2: Run the focused tests and confirm missing-symbol failure**

Run: `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox --filter TapCoordinateMappingTests`

- [ ] **Step 3: Implement aspect-fit mapping, clamping, finite-size guards, and strict status parsing**

```swift
public func mapClickToDevicePoint(
    clickInView: CGPoint,
    viewSize: CGSize,
    imagePixelSize: CGSize,
    deviceSpaceSize: CGSize
) -> CGPoint
```

- [ ] **Step 4: Run the focused tests green and commit**

Commit: `feat(core): map screenshot clicks to device coordinates`

### Task 2: Defensive text-source parser

**Files:**
- Create: `Sources/PhoneHubCore/TextSourceParser.swift`
- Create: `Tests/PhoneHubCoreTests/TextSourceParserTests.swift`

**Interfaces:**
- Produces: `TextSourceFormat`, `TextSourceParseError`, and `TextSourceParser.parse(data:format:) -> [String]`

- [ ] **Step 1: Write failing TXT tests** for numbered, mixed bullet, blank-block, whole-document, control-character, empty, and item-cap behavior.

- [ ] **Step 2: Run the parser test class red** with the requested test environment.

- [ ] **Step 3: Implement TXT parsing and shared sanitization** using anchored regular expressions and Unicode-scalar filtering.

- [ ] **Step 4: Run TXT tests green**.

- [ ] **Step 5: Write failing JSON tests** for both accepted roots, wrong member types, wrong roots, invalid UTF-8, oversized data, and nesting depth over 64.

- [ ] **Step 6: Implement a string-aware JSON depth scan and `JSONSerialization` root validation**, then run JSON tests green.

- [ ] **Step 7: Write failing XML tests** for the accepted structure, malformed XML, unexpected nesting/elements, DTD, entity, and XXE declarations.

- [ ] **Step 8: Implement a strict `XMLParserDelegate`** with `shouldResolveExternalEntities = false`, pre-reject declarations, and run all parser tests green.

- [ ] **Step 9: Commit**

Commit: `feat(core): parse defensive text source imports`

### Task 3: Text sources, binding resolution, and persistent draft

**Files:**
- Create: `Sources/PhoneHubCore/TextSource.swift`
- Create: `Sources/PhoneHubCore/TextSourceStore.swift`
- Create: `Sources/PhoneHubCore/BuilderDraft.swift`
- Create: `Sources/PhoneHubCore/BuilderDraftStore.swift`
- Modify: `Sources/PhoneHubCore/Automation.swift`
- Create: `Tests/PhoneHubCoreTests/TextSourceTests.swift`
- Create: `Tests/PhoneHubCoreTests/TextSourceStoreTests.swift`
- Create: `Tests/PhoneHubCoreTests/BuilderDraftStoreTests.swift`
- Modify: `Tests/PhoneHubCoreTests/AutomationTests.swift`

**Interfaces:**
- Produces: `TextSource`, `TextSourceMode`, `TextSourceRef`, `TextSourceResolution`
- Produces: `resolveTextSourceBindings(steps:bindings:sources:) throws -> TextSourceResolution`
- Produces: `TextSourceStore.resolve(_:)`, `commit(_:)`, and current-preview resolution
- Produces: `BuilderDraft` and `BuilderDraftStore` mutation/persistence methods
- Extends: `Automation.textSourceBindings: [UUID: TextSourceRef]`

- [ ] **Step 1: Write failing model/resolution tests** proving same-source reuse, static behavior, cycle wrap metadata, missing source rejection, and non-typeText binding rejection.

- [ ] **Step 2: Run red, implement minimal pure resolution, and run green**.

- [ ] **Step 3: Write failing store tests** proving successful commit advances each cycle source once, static does not advance, reset/delete persist, and cursor normalization survives reload.

- [ ] **Step 4: Run red, implement atomic `TextSourceStore`, and run green**.

- [ ] **Step 5: Write failing compatibility and draft tests** proving old automation JSON decodes with empty bindings and draft steps/bindings/platform survive reload.

- [ ] **Step 6: Run red, add custom compatible `Automation` decoding plus `BuilderDraftStore`, and run green**.

- [ ] **Step 7: Commit**

Commit: `feat(core): persist builder drafts and text bindings`

### Task 4: Exactly-one-action agent capture

**Files:**
- Modify: `Sources/PhoneHubCore/AutomationCapture.swift`
- Modify: `Sources/PhoneHubCore/AutomationPlan.swift`
- Modify: `Sources/PhoneHub/AutomationEngine.swift`
- Modify: `Tests/PhoneHubCoreTests/AutomationCaptureTests.swift`
- Modify: `Tests/PhoneHubCoreTests/AutomationPlanTests.swift`
- Modify: `Tests/PhoneHubTests/AutomationEngineTests.swift`

**Interfaces:**
- Produces: `automationSteps(from:) -> [AutomationStep]`
- Produces: `buildBuilderActionPlan(device:backend:preferKnownSteps:)`
- Produces: `AutomationEngine.runBuilderAction(...)` and observable `isBuilderAction`

- [ ] **Step 1: Write failing capture tests** showing observational tools are filtered and action calls preserve order without inserted waits.

- [ ] **Step 2: Run red, expose the pure capture mapper, and run green**.

- [ ] **Step 3: Write failing plan tests** proving the builder preamble permits observation, requires exactly one mutating action, has a small tool-call cap, and preserves Android serial context.

- [ ] **Step 4: Run red, implement `buildBuilderActionPlan`, and run green**.

- [ ] **Step 5: Write engine-state tests**, implement builder launch/origin cleanup through the existing launch path, run focused engine tests green, and commit.

Commit: `feat: add single-action builder agent turns`

### Task 5: Runner and community source resolution

**Files:**
- Modify: `Sources/PhoneHub/AutomationRunner.swift`
- Modify: `Sources/PhoneHub/AutomationsPanel.swift`
- Modify: `Sources/PhoneHub/CommunityShareSheet.swift`
- Modify: `Sources/PhoneHub/PhoneHubApp.swift`
- Create: `Tests/PhoneHubTests/AutomationRunnerTextSourceTests.swift`
- Modify: `Tests/PhoneHubCoreTests/TextSourceTests.swift`

**Interfaces:**
- `AutomationRunner` consumes `TextSourceStore`.
- Community sharing consumes preview-resolved steps and never commits cursors.

- [ ] **Step 1: Add failing runner tests** for source substitution before invocation, success-only cursor advancement, failure/stopped non-advancement, and wrapped log output.

- [ ] **Step 2: Run red, resolve before MCP start, commit only at terminal success, and run green**.

- [ ] **Step 3: Add failing community-preview tests**, resolve current text without cursor mutation, and run green.

- [ ] **Step 4: Wire one app-level `TextSourceStore` into all run/share paths and commit**.

Commit: `feat: resolve text sources during automation runs`

### Task 6: Manual tap picker

**Files:**
- Create: `Sources/PhoneHub/PhoneMcpClientFactory.swift`
- Create: `Sources/PhoneHub/ManualTapPickerModel.swift`
- Create: `Sources/PhoneHub/ManualTapPicker.swift`
- Modify: `Sources/PhoneHub/AutomationRunner.swift`

**Interfaces:**
- Produces: a shared direct-client factory for iOS/Android.
- Produces: picker result preserving the original tap kind, ID, and duration.

- [ ] **Step 1: Extract the existing direct-client construction without behavior change** and run `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox --filter AutomationRunnerTextSourceTests`.

- [ ] **Step 2: Implement the picker model** to validate serials, request a current screenshot, request iOS status, decode PNG pixel dimensions, and expose retryable errors.

- [ ] **Step 3: Implement the screenshot sheet** with aspect-fit click capture, dim overlay, marker, optional label, Retake/Confirm/Cancel, and lifecycle client cleanup.

- [ ] **Step 4: Build and fix compile/accessibility issues, then commit**.

Commit: `feat: add screenshot-based manual tap picker`

### Task 7: Builder and text-source management UI

**Files:**
- Create: `Sources/PhoneHub/AutomationStepPresentation.swift`
- Create: `Sources/PhoneHub/BuilderView.swift`
- Create: `Sources/PhoneHub/BuilderTimelineRow.swift`
- Create: `Sources/PhoneHub/TextSourcesSheet.swift`
- Modify: `Sources/PhoneHub/AutomationStepRow.swift`
- Modify: `Sources/PhoneHub/PresetsPanel.swift`
- Modify: `Sources/PhoneHub/Sidebar.swift`
- Modify: `Sources/PhoneHub/PhoneHubApp.swift`

**Interfaces:**
- Builder consumes focused device, stores, engine, runner, backend, and busy flags.
- Timeline rows edit steps/bindings and invoke tap picking or insertion callbacks.

- [ ] **Step 1: Extract shared step icon/title/summary helpers** and compile before changing behavior.

- [ ] **Step 2: Implement `TextSourcesSheet`** with security-scoped file importing for TXT/JSON/XML, pre-read file-size cap, mode editing, cursor reset, and deletion.

- [ ] **Step 3: Implement timeline rows and `List`** with drag reorder, delete, insert-after, wait editing, literal/source type-text selection, AI prompt editing, and tap target editing.

- [ ] **Step 4: Implement builder message turns** with running/ok/failed status, exactly-one capture acceptance, durable draft mutations, platform pin/mismatch state, clear/save/run controls, and runner log display.

- [ ] **Step 5: Replace only `commandBox` in `PresetsPanel`, preserve preset listing/run-result behavior, wire stores from app/sidebar, build, and commit**.

Commit: `feat: replace command box with timeline builder`

### Task 8: Review and verification

**Files:** all changed files.

- [ ] **Step 1: Run focused new tests and `git diff --check`**.

- [ ] **Step 2: Perform adversarial self-review** against every requirement with file/line evidence and verdict `Ready to merge: Yes / No / With fixes`.

- [ ] **Step 3: Fix every Critical/Important finding via red-green tests where pure logic changes**, then repeat review.

- [ ] **Step 4: Run the full suite**

Run: `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox`

- [ ] **Step 5: Run the full build**

Run: `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`

- [ ] **Step 6: Verify clean status, conventional commits, and Benas author/committer metadata; commit any final review fixes**.
