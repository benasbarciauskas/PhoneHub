# LLM Providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add selectable Claude/Codex CLI and OpenRouter/OpenAI/Anthropic API backends without exposing API keys outside macOS Keychain.

**Architecture:** Preserve CLI process execution and add a normalized provider protocol plus a PhoneHub-owned MCP tool loop for API backends. Persist only backend/model configuration and expose all runtime output through existing `StreamEvent` cases.

**Tech Stack:** Swift 5.9, macOS 14, Foundation URLSession, Security.framework, SwiftUI, Swift Testing/XCTest.

## Global Constraints

- Keys exist only in Keychain service `com.phonehub.llm`; never log, encode, bundle, or include them in errors.
- Claude and Codex CLI argument behavior remains unchanged.
- Reuse the existing platform MCP wiring and `McpDirectClient`.
- Keep source files below 500 lines and add no dependency.
- Before each commit run `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox`.
- Before completion also run `swift build --disable-sandbox`.

---

### Task 1: Keychain and non-secret configuration

**Files:**
- Create: `Sources/PhoneHubCore/KeychainStore.swift`
- Create: `Sources/PhoneHubCore/LLMAppConfig.swift`
- Create: `Tests/PhoneHubCoreTests/KeychainStoreTests.swift`
- Create: `Tests/PhoneHubCoreTests/LLMAppConfigTests.swift`

**Interfaces:**
- Produces: `KeychainStore(service:)`, `setKey(provider:key:)`, `key(provider:)`, `deleteKey(provider:)`, `LLMAppConfig`, and `LLMConfigStore`.

- [ ] Write tests proving config round-trip/defaults contain models but no key property, and an env-gated unique-service Keychain add/update/read/delete round-trip.
- [ ] Run filtered tests and confirm compile failures name the missing types.
- [ ] Implement Security `SecItemAdd`, `SecItemUpdate`, `SecItemCopyMatching`, and `SecItemDelete`; map only status codes into errors.
- [ ] Implement Codable config defaults, legacy-backend migration, and UserDefaults JSON persistence.
- [ ] Run the full required suite, then commit `feat: add secure LLM configuration`.

### Task 2: Provider mappings and clients

**Files:**
- Create: `Sources/PhoneHubCore/LLMProvider.swift`
- Create: `Sources/PhoneHubCore/OpenAICompatibleProvider.swift`
- Create: `Sources/PhoneHubCore/AnthropicProvider.swift`
- Create: `Tests/PhoneHubCoreTests/LLMProviderTests.swift`

**Interfaces:**
- Produces: `LLMMessage`, `LLMToolDefinition`, `LLMToolCall`, `LLMResponse`, `LLMProvider`, pure builders/parsers, and URLSession provider clients.

- [ ] Write fixtures/tests for OpenAI/OpenRouter request headers and JSON, Anthropic request JSON, assistant text, multiple tool calls, malformed responses, and redacted HTTP errors.
- [ ] Run filtered tests and confirm failures are caused by missing provider APIs.
- [ ] Implement normalized message/tool types and OpenAI-compatible pure request/response mapping.
- [ ] Implement Anthropic pure request/response mapping and both URLSession clients with status-only errors.
- [ ] Run the full required suite, then commit `feat: add API LLM providers`.

### Task 3: API tool runtime

**Files:**
- Create: `Sources/PhoneHubCore/ApiAgentRuntime.swift`
- Create: `Sources/PhoneHubCore/PhoneControlTools.swift`
- Create: `Tests/PhoneHubCoreTests/ApiAgentRuntimeTests.swift`

**Interfaces:**
- Consumes: `LLMProvider`, `AutomationPlan`, `McpDirectClient`, and `StreamEvent`.
- Produces: `ApiAgentRuntime.run(...)`, fixed tool definitions, and pure response decision helpers.

- [ ] Write tests for the ten required tool schemas, text completion, `NEED_INPUT`, tool continuation, tool-result messages, invalid argument JSON, and max-step failure.
- [ ] Run filtered tests and confirm missing-runtime failures.
- [ ] Implement the pure decision helpers and tool schemas.
- [ ] Implement the async MCP loop with cancellation cleanup and event emission.
- [ ] Run the full required suite, then commit `feat: add API agent tool runtime`.

### Task 4: Backend and engine wiring

**Files:**
- Modify: `Sources/PhoneHubCore/AutomationPlan.swift`
- Modify: `Sources/PhoneHubCore/BackendAvailability.swift`
- Modify: `Sources/PhoneHubCore/CodexStreamParser.swift`
- Modify: `Sources/PhoneHub/AutomationEngine.swift`
- Modify: `Sources/PhoneHub/ChatEngine.swift`
- Modify: matching core/app tests.

**Interfaces:**
- Consumes: configuration, providers, runtime.
- Produces: five `AgentBackend` cases with CLI/API dispatch in both engines.

- [ ] Extend plan/availability tests first, including exact existing CLI arguments and injected present/absent API keys; run them red.
- [ ] Add backend cases/properties and make API plan argument APIs return no process arguments while retaining MCP plan data.
- [ ] Add engine tests around injected runtime launch/event handling; run them red, then implement one API branch in each engine.
- [ ] Ensure API reply/chat history behavior and cancellation do not use CLI session IDs or temp MCP config files.
- [ ] Run the full required suite, then commit `feat: wire API backends into agents`.

### Task 5: Settings UI and migration

**Files:**
- Modify: `Sources/PhoneHub/PhoneHubApp.swift`
- Modify: `Sources/PhoneHub/Sidebar.swift`
- Create: `Sources/PhoneHub/LLMSettingsView.swift`
- Create/modify: matching `PhoneHubTests` configuration/helper tests.

**Interfaces:**
- Consumes: `LLMConfigStore`, `KeychainStore`, all `AgentBackend` cases.
- Produces: settings sheet and a binding replacing legacy `@AppStorage("agentBackend")`.

- [ ] Write tests for provider display names/status and config migration; run them red.
- [ ] Inject one observable settings model at app root, bind selected backend through Sidebar/Stage, and preserve preset overrides.
- [ ] Add the settings sheet with picker, per-provider model `TextField`, write-only `SecureField`, save/delete, and key status.
- [ ] Run the full required suite and build, then commit `feat: add LLM provider settings`.

### Task 6: Final review and verification

- [ ] Review `origin/main..HEAD` for CLI regressions, actor/cancellation races, unsafe error interpolation, secret persistence, and files over 500 lines; record file/line findings and fix all important issues with tests first.
- [ ] Run the full required test command and `swift build --disable-sandbox` from a clean working tree.
- [ ] Scan tracked source/config/diff for secret-like values and Keychain violations; verify commit author/committer identity and that no push occurred.
- [ ] Report commit list, test tail, build result, and security confirmation.
