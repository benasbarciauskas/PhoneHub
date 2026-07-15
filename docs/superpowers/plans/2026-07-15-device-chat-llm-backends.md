# Device Chat + Pluggable LLM Backends + Skills Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chat with an LLM agent (eyes + hands on the focused phone via mirroir/androir MCP) inside PhoneHub, with persisted per-device history, a pluggable claude/codex backend, CLI-availability hints, and a skills-repo setup script.

**Architecture:** Reuse the existing preset plumbing (`AutomationPlan` arg building, `StreamingProcess`, `StreamJSONParser`). Chat = first message spawns the same headless agent; every later message is a `--resume`. New `ChatEngine` (UI-side) + `ChatStore` (Core, persisted JSON per device). Backend abstraction = `AgentBackend` enum on `AutomationPlan` with per-backend argv builders and stream parsers.

**Tech Stack:** Swift 5.9 SwiftPM, SwiftUI, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-15-device-chat-llm-backends-design.md`

## Global Constraints

- macOS 14+, targets `PhoneHub` (UI) + `PhoneHubCore` (logic). Logic + parsing goes in Core so it's unit-testable.
- PhoneHub never stores or reads API keys. Backends = host user's own `claude` / `codex` CLI login.
- Validate device serials before argv use (existing `isValidSerial`); argv arrays only, never shell strings.
- Tests: `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox`
- Commit after each task (Conventional Commits). Keep files under ~500 lines.
- **Existing behavior note:** the app has ONE global run slot (`AutomationEngine.isBusy`). A chat turn and a preset run are mutually exclusive globally. Chat must respect `engine.isBusy` and the engine must respect `chatEngine.isBusy` (Task 5).

---

## Phase 1 — Chat on the claude backend

### Task 1: `AgentBackend` enum + backend-aware `AutomationPlan`

**Files:**
- Modify: `Sources/PhoneHubCore/AutomationPlan.swift`
- Test: `Tests/PhoneHubCoreTests/AutomationPlanTests.swift` (extend existing)

**Interfaces:**
- Produces: `public enum AgentBackend: String, Codable, CaseIterable, Sendable { case claude, codex }`
- Produces: `AutomationPlan.backend: AgentBackend` (new stored property, default `.claude` in `buildAutomationPlan`)
- `arguments(mcpConfigPath:)` / `resumeArguments(...)` switch on backend; `.claude` output byte-identical to today. `.codex` cases `fatalError("codex backend: Task 9")` is NOT acceptable — instead return the codex argv per Task 9's shape now if trivial, otherwise leave `.codex` out of this task by making the switch exhaustive with a temporary internal `codexArguments` returning `[]` and a `// Phase 2` marker plus a test asserting claude output unchanged. (Keeps main shippable.)

- [ ] **Step 1: Failing tests** — extend `AutomationPlanTests`: `testClaudeArgumentsUnchangedByBackendField` (build plan for an iOS device, assert argv equals the exact current flag list), `testBackendDefaultsToClaude`.
- [ ] **Step 2: Run tests** — fail (no `backend` field).
- [ ] **Step 3: Implement** — add enum + field + switch. All existing call sites compile unchanged (default parameter).
- [ ] **Step 4: Tests pass.**
- [ ] **Step 5: Commit** — `feat(core): AgentBackend enum on AutomationPlan (claude unchanged)`

### Task 2: Chat plan building

**Files:**
- Modify: `Sources/PhoneHubCore/AutomationPlan.swift`
- Test: `Tests/PhoneHubCoreTests/AutomationPlanTests.swift`

**Interfaces:**
- Produces: `public func buildChatPlan(device: Device, backend: AgentBackend = .claude) throws -> AutomationPlan`
- Produces: `public let chatSystemPreamble: String`

Chat plan = same MCP config / allowedTools / serial validation as `buildAutomationPlan` (extract the shared per-platform block into a private helper `platformWiring(for:) throws -> (server: String, mcpJSON: String, allowedTools: String, deviceContext: String)` used by both builders — DRY, no behavior change). Differences: `prompt` is empty at build time (ChatEngine passes the user's message as the `-p` value — see Task 4 interface), `maxTurns` = 25, preamble:

```swift
public let chatSystemPreamble = """
You are operating a phone through the attached tools, in an interactive chat \
with the user. Answer conversationally. When the user asks about the screen, \
look at it with the tools and describe what you see. When asked to act, act \
with the tools. Use only the attached phone-control tools. If unsure, ask the \
user instead of guessing — just end your reply with the question.
"""
```

`AutomationPlan` gains `func arguments(mcpConfigPath: String, promptOverride: String?) -> [String]` OR simpler: make `prompt` a `var` and have ChatEngine copy the plan with the message as prompt. Pick the simplest that keeps `AutomationPlan` `Equatable` and tests readable (recommendation: `var prompt`).

- [ ] **Step 1: Failing tests** — `testChatPlanIOSUsesMirroirAndChatPreamble`, `testChatPlanAndroidValidatesSerial` (invalid serial throws `.invalidSerial`), `testChatPlanAndroidMentionsSerialInDeviceContextViaPreamble` (device context must still reach the agent: assert serial instruction present in `systemPreamble` for chat plans — chat moves deviceContext into the preamble since `-p` carries the user message).
- [ ] **Step 2: Fail.**
- [ ] **Step 3: Implement** (incl. the shared-wiring refactor; run full suite to prove `buildAutomationPlan` unchanged).
- [ ] **Step 4: Pass.**
- [ ] **Step 5: Commit** — `feat(core): buildChatPlan + shared platform wiring`

### Task 3: `ChatStore` — persisted per-device transcripts

**Files:**
- Create: `Sources/PhoneHubCore/ChatStore.swift`
- Test: `Tests/PhoneHubCoreTests/ChatStoreTests.swift`

**Interfaces (produces):**

```swift
public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant, tool, system }
    public let id: UUID
    public let role: Role
    public let text: String
    public let timestamp: Date
    public init(role: Role, text: String, timestamp: Date = .now)
}

public struct DeviceChat: Codable, Equatable, Sendable {
    public var messages: [ChatMessage]
    public var sessionId: String?
    public var backend: AgentBackend
    public static let empty: DeviceChat // messages: [], sessionId: nil, backend: .claude
}

public final class ChatStore {
    public init(directory: URL) // prod: ~/Library/Application Support/PhoneHub/chats
    public func load(deviceId: String) -> DeviceChat
    public func save(_ chat: DeviceChat, deviceId: String)
}
```

Rules: follow `PresetStore.swift`'s existing load/save pattern (read it first; same JSON encoder config, atomic writes). File name = sanitized deviceId: replace every character outside `[A-Za-z0-9._-]` with `_` (device serials/UDIDs are external input — never let them become path components raw), suffix `.json`. `load` returns `.empty` on missing/corrupt file (log, don't crash). Cap persisted messages at 200 (drop oldest on save).

- [ ] **Step 1: Failing tests** — round-trip save/load; corrupt file → `.empty`; deviceId `"../evil/../../x"` produces a file strictly inside the store directory (assert resolved path has directory as prefix); 250 messages → 200 after save/load.
- [ ] **Step 2: Fail.** — run the new test file.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Pass.**
- [ ] **Step 5: Commit** — `feat(core): ChatStore with sanitized per-device persistence`

### Task 4: Backend availability detection

**Files:**
- Create: `Sources/PhoneHubCore/BackendAvailability.swift`
- Test: `Tests/PhoneHubCoreTests/BackendAvailabilityTests.swift`

**Interfaces (produces):**

```swift
public enum BackendStatus: Equatable, Sendable {
    case available(path: String)
    case missing(hint: String)
}
public enum BackendAvailability {
    /// resolver injectable for tests; prod default wraps resolveTool + ~/.local/bin fallback
    public static func check(_ backend: AgentBackend,
                             resolver: (String) -> String? = defaultResolver) -> BackendStatus
}
```

Hints (exact copy): claude → `"Install the Claude CLI (https://claude.com/claude-code) and run \`claude\` once to log in. PhoneHub uses your own login — it stores no keys."`; codex → `"Install the Codex CLI (npm i -g @openai/codex) and run \`codex\` once to log in. PhoneHub uses your own login — it stores no keys."`

Move `AutomationEngine.resolveClaude()`'s PATH + `~/.local/bin` logic into `defaultResolver` (generalized to any binary name) and have `AutomationEngine` call `BackendAvailability` instead (delete the private duplicate).

- [ ] **Step 1: Failing tests** — resolver returns path → `.available`; returns nil → `.missing` with the exact hint text per backend.
- [ ] **Step 2: Fail.**
- [ ] **Step 3: Implement + rewire AutomationEngine.**
- [ ] **Step 4: Full suite passes.**
- [ ] **Step 5: Commit** — `feat(core): backend availability check with actionable hints`

### Task 5: `ChatEngine`

**Files:**
- Create: `Sources/PhoneHub/ChatEngine.swift`
- Test: `Tests/PhoneHubCoreTests/` — only pure pieces live in Core; keep ChatEngine thin. Anything testable (e.g. transcript-append rules, stale-session retry decision) goes in Core as pure funcs if it grows.

**Interfaces:**
- Consumes: `buildChatPlan`, `ChatStore`, `BackendAvailability`, `StreamingProcess`, `StreamJSONParser`, `AutomationPlan.arguments/resumeArguments`.
- Produces (used by Task 6 UI):

```swift
@Observable @MainActor final class ChatEngine {
    enum TurnState: Equatable { case idle, running, failed(String) }
    private(set) var chat: DeviceChat
    private(set) var turnState: TurnState
    private(set) var streamingText: String   // live partial assistant text
    var isBusy: Bool                          // turnState == .running
    func bind(device: Device)                 // load persisted chat for device
    func send(_ text: String, on device: Device, presetEngineBusy: Bool)
    func stop()
    func newChat(deviceId: String)
}
```

Behavior (mirror `AutomationEngine` patterns exactly — same spawn/exit/MainActor hopping):
- `send`: guard not busy, guard `!presetEngineBusy` (append system bubble "A preset run is active — wait or stop it." if it is), trim text, availability-check backend (missing → system bubble with hint, no spawn). First message of a session (`chat.sessionId == nil`): build chat plan, set `plan.prompt = text`, write temp MCP config (reuse the same temp-file pattern; keep configURL for the whole chat session, delete on `newChat`/deinit/app quit), spawn. Later messages: `resumeArguments(sessionId:reply:)`.
- Stream handling: reuse `StreamJSONParser.parseLine`. `assistant` text events accumulate into `streamingText`; tool events append `ChatMessage(role: .tool, text: "▸ <toolName>")`; on `result`/exit, flush `streamingText` into a `.assistant` message, capture sessionId (both event types, same as AutomationEngine:247-258), persist via ChatStore.
- Resume failure (spawn exits non-zero AND stderr/reason mentions the session, or exit != 0 on a resume turn): retry ONCE as a fresh session (sessionId = nil, same message), then system bubble with the error. Keep transcript.
- `stop()`: terminate process; flush partial streamingText with suffix `" — (stopped)"`; state idle; session id kept.
- `newChat`: clear messages + sessionId (keep backend), persist, delete temp config.
- Every persisted mutation → `store.save`.

- [ ] **Step 1: Failing tests for pure decision helpers** — put `ChatTurn.shouldRetryAsFresh(exitCode:isResumeTurn:alreadyRetried:) -> Bool` in Core with tests (true only for: non-zero exit, resume turn, not yet retried).
- [ ] **Step 2: Fail → implement helper → pass.**
- [ ] **Step 3: Implement ChatEngine** using the helper. Build the app target (`swift build`).
- [ ] **Step 4: Full suite + build pass.**
- [ ] **Step 5: Commit** — `feat: ChatEngine — conversational agent turns with resume + persistence`

### Task 6: Chat UI

**Files:**
- Create: `Sources/PhoneHub/ChatPanel.swift`
- Modify: `Sources/PhoneHub/Sidebar.swift` (add a Presets|Chat segmented picker or tab where PresetsPanel is mounted), `Sources/PhoneHub/PhoneHubApp.swift` (create + inject `ChatEngine`, wire mutual-exclusion flags both ways: PresetsPanel run buttons disabled while `chatEngine.isBusy`)

**Structure (follow existing PresetsPanel styling/idioms):**
- Transcript: `ScrollView` + `LazyVStack`; `.user` right-aligned accent bubble; `.assistant` left plain; `.tool` monospaced secondary one-liner; `.system` centered secondary italic. Auto-scroll to bottom on append (`ScrollViewReader`).
- While running: streamingText shown as a live assistant bubble + subtle progress indicator; input disabled; **Stop** visible.
- Bottom bar: `TextField` (submits on ⏎), Send button, overflow menu with **New chat**.
- Device switch → `chatEngine.bind(device:)` (transcript swaps to that device's history).
- No device focused → placeholder text "Focus a device to chat."

- [ ] **Step 1: Implement view + wiring.**
- [ ] **Step 2: `swift build` + full `swift test` pass.**
- [ ] **Step 3: Manual smoke** — `./build-app.sh && open PhoneHub.app`; with a real iOS device focused, send "What's on screen right now?"; verify streamed description lands as assistant bubble; follow-up "open Settings" acts; relaunch app → transcript restored.
- [ ] **Step 4: Commit** — `feat: device chat panel with persisted history`

### Task 7: Skills setup script + status line

**Files:**
- Create: `scripts/setup-skills.sh`
- Modify: `Sources/PhoneHub/PresetsPanel.swift` (passive status line), `Sources/PhoneHubCore/` small helper `SkillsStatus.swift`
- Test: `Tests/PhoneHubCoreTests/SkillsStatusTests.swift`

**Script (complete):**

```bash
#!/usr/bin/env bash
# Install/update the device-automation skills repos the MCP servers read.
set -euo pipefail

install_or_update() {
  local repo="$1" dest="$2"
  if [ -d "$dest/.git" ]; then
    echo "Updating $dest…"
    git -C "$dest" pull --ff-only
  else
    echo "Cloning $repo → $dest…"
    mkdir -p "$(dirname "$dest")"
    git clone --depth 1 "$repo" "$dest"
  fi
}

# iOS: mirroir app-knowledge / obstacle patterns
install_or_update "https://github.com/jfarcand/mirroir-skills" "$HOME/.mirroir-mcp/skills"

# Android: no published androir skills repo yet — placeholder, not an error.
echo "androir: no skills repo published yet — skipping."

echo "Done."
```

**Core helper:** `public enum SkillsStatus { public static func mirroirSkillsInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool }` → checks `<home>/.mirroir-mcp/skills` directory exists. UI: single secondary-text line in PresetsPanel footer: installed → `iOS skills: installed ✓`; else `iOS skills: not installed — run scripts/setup-skills.sh`.

- [ ] **Step 1: Failing test** — temp dir with/without `.mirroir-mcp/skills` → bool.
- [ ] **Step 2: Fail → implement → pass.**
- [ ] **Step 3: Run script for real; verify `~/.mirroir-mcp/skills` populated; run again → idempotent pull.**
- [ ] **Step 4: `shellcheck scripts/setup-skills.sh` clean (if installed).**
- [ ] **Step 5: Commit** — `feat: skills-repo setup script + install status line`

### Task 8: E2E gate + README

**Files:**
- Modify: `README.md` (Device Chat section; "bring your own LLM" note; skills setup; Android caveat if androir unpublished)

- [ ] **Step 1: Verify androir publish state** — `npm view androir-mcp version` (unsandboxed / with network). If missing: README + a system-bubble hint when an Android chat/preset spawn fails with npx resolution error is OUT of scope beyond the README caveat — record actual state.
- [ ] **Step 2: Real-device e2e (manual, recorded in PR):** preset run on iOS device (existing feature — first-ever verification) + chat exchange: describe screen → one action. Android same IF androir resolves.
- [ ] **Step 3: README updates.**
- [ ] **Step 4: Commit** — `docs: device chat + BYO-LLM + skills setup; record e2e verification`

## Phase 2 — Codex backend

### Task 9: Codex argv builder

**Files:**
- Modify: `Sources/PhoneHubCore/AutomationPlan.swift`
- Test: `Tests/PhoneHubCoreTests/AutomationPlanTests.swift`

**IMPORTANT — validate flags against the real CLI first:** run `codex exec --help` and `codex exec resume --help` on this host; adjust below to what the installed CLI actually accepts, and note the verified version in the commit message.

Expected shape (verify): initial —

```
codex exec --json --skip-git-repo-check \
  -c mcp_servers.<name>.command=npx \
  -c 'mcp_servers.<name>.args=["-y","mirroir-mcp","--dangerously-skip-permissions"]' \
  "<prompt with system preamble prepended>"
```

resume — `codex exec resume <sessionId> --json "<reply>"` (+ same `-c` overrides). Codex has no `--append-system-prompt`/`--allowedTools`/`--max-turns` equivalents: prepend the preamble to the prompt; step cap enforced by instruction text only; document both deltas in code comments. `--dangerously-skip-permissions`-style approval bypass for codex tool use: use `-c approval_policy=never` and sandbox default (MCP tools are the only side-effect surface; codex must NOT get workspace-write — it's driving a phone, not editing files).

- [ ] **Step 1: Failing tests** — `testCodexInitialArguments`, `testCodexResumeArguments` (exact argv arrays).
- [ ] **Step 2: Fail → implement → pass.**
- [ ] **Step 3: Commit** — `feat(core): codex backend argv (verified against codex <version>)`

### Task 10: `CodexStreamParser`

**Files:**
- Create: `Sources/PhoneHubCore/CodexStreamParser.swift`
- Test: `Tests/PhoneHubCoreTests/CodexStreamParserTests.swift` (fixture JSONL lines captured from a real `codex exec --json` run — capture during implementation, commit fixtures inline as test constants)

**Interfaces:**
- Produces: `public enum CodexStreamParser { public static func parseLine(_ line: String) -> StreamEvent }` mapping codex JSONL → the SAME `StreamEvent` enum `StreamJSONParser` emits (read `StreamJSONParser.swift` first; reuse its enum, do not invent a parallel one). Mapping: thread/session id event → `.system(_, sid)`; agent text delta/message → assistant text; tool/command events → tool-use event; final message → `.result`. Unknown lines → whatever `StreamJSONParser` returns for unknowns (ignore).
- Dispatch: a single `parseLine(line:backend:)` entry point or a protocol — pick the smallest change to `AutomationEngine.handle` / `ChatEngine` (a switch on plan.backend is fine).

- [ ] **Step 1: Capture real fixtures** — run `codex exec --json 'say hi'` once; copy 5-10 representative lines.
- [ ] **Step 2: Failing tests over fixtures → implement → pass.**
- [ ] **Step 3: Commit** — `feat(core): codex stream parser mapped to shared StreamEvent`

### Task 11: Backend picker + wiring

**Files:**
- Modify: `Sources/PhoneHub/PhoneHubApp.swift` or a small settings surface (simplest idiomatic spot — e.g. app menu or a gear popover in Sidebar): app-default backend stored in `UserDefaults` (`@AppStorage("agentBackend")`).
- Modify: `Sources/PhoneHubCore/Preset.swift` + `PresetEditSheet.swift`: optional per-preset backend override (`backend: AgentBackend?`, nil = app default; Codable default nil so existing presets.json loads — add decode test).
- Modify: `AutomationEngine` + `ChatEngine`: thread chosen backend into plan builders; availability-check the chosen backend before spawn (hint bubble/log line from Task 4).
- Test: preset JSON backward-compat decode test; plan builder honors override.

- [ ] **Step 1: Failing tests → implement → pass (full suite).**
- [ ] **Step 2: Manual smoke: switch default to codex, chat once on real device; if resume unsupported/broken in practice → ship stateless mode: UI badge "codex: stateless mode", each send prepends rolled-up prior transcript (last 20 messages, plain text) to the prompt. Record which mode shipped.**
- [ ] **Step 3: README: backend section.**
- [ ] **Step 4: Commit** — `feat: per-preset + app-default LLM backend picker`

---

## Self-review notes

- Spec coverage: chat (T2-T6), persistence per user (T3), backends (T1, T9-T11), availability hints (T4), skills (T7), e2e gate + androir check + README (T8). BYO-key guarantee: no key handling anywhere; hints copy in T4.
- Spec deviation (intentional): concurrency is one global run slot (matches existing engine), not per-device; spec's "different devices independent" dropped — simpler and true to current code.
- Type consistency: `StreamEvent` reused across parsers (T10 must read `StreamJSONParser.swift` and reuse its enum name — actual name to be confirmed in code; if it differs, keep the code's name everywhere).
