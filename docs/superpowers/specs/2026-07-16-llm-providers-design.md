# LLM Providers Design

## Goal

PhoneHub supports the existing Claude and Codex CLI agents plus OpenRouter,
OpenAI, and Anthropic APIs for preset runs and device chat. CLI execution keeps
its current process-owned MCP loop. API execution uses PhoneHub's existing
`McpDirectClient` to run phone tools until the provider returns a final turn.

## Configuration and secrets

`LLMAppConfig` is Codable and stores only the selected backend and one model
name per API provider in UserDefaults JSON. The legacy `agentBackend` value is
migrated when no new config exists. API keys use `KeychainStore` backed by
Security.framework generic-password items with service `com.phonehub.llm` and
provider raw value as account. Key entry is a `SecureField`; values are never
read back into UI, UserDefaults, logs, errors, or committed files.

## Provider boundary

`LLMProvider` exposes one async `send(messages:tools:)` operation returning an
`LLMResponse` containing assistant text and normalized tool calls. OpenAI and
OpenRouter share OpenAI-compatible pure JSON mapping, while Anthropic has its
own pure mapping. Network clients use URLSession and create only redacted,
status-based errors; response bodies are not included in errors.

## API runtime

`ApiAgentRuntime` receives an `AutomationPlan`, model, provider, and an MCP
client created from the plan's existing MCP configuration. It starts MCP,
advertises the fixed phone-control tool schemas, and loops up to `maxTurns`.
Each provider response emits the existing `StreamEvent` values. Tool calls emit
`.toolUse`, execute through `McpDirectClient.callTool`, emit `.toolResult`, and
append provider-appropriate normalized tool-result messages. Plain text emits
`.assistantText`; a `NEED_INPUT:` line emits `.needInput`; terminal success or
step exhaustion emits `.result`. Cancellation always stops MCP.

## Engine integration

`AgentBackend` gains `openrouter`, `openai`, and `anthropic`, plus `isCLI` and
`isAPI`. `AutomationPlan` arguments remain byte-for-byte equivalent for Claude
and Codex; API cases do not produce CLI arguments. `AutomationEngine` and
`ChatEngine` branch at launch: CLI follows the existing process path, API starts
an async runtime task and consumes the same events through shared handlers.
Chat sends its persisted history on each API turn; no API conversation ID is
stored. Preset backend overrides remain unchanged because they already persist
`AgentBackend`.

## Availability and settings

CLI availability resolves binaries exactly as before. API availability checks
only whether a non-empty key exists and otherwise returns `Add your <provider>
API key in Settings`. The gear opens a small settings sheet with backend picker,
provider-specific model field, write-only key `SecureField`, save/delete actions,
and a `key saved ✓` or `not set` status.

## Testing and security gates

Pure fixture tests cover all request builders and response parsers, including
text and tool calls. Runtime helper tests cover continue/final/need-input/max-step
decisions. Configuration tests prove no key field is encoded. Keychain tests use
a unique test service and clean up, with the live Security round-trip gated by
`PHONEHUB_LIVE_KEYCHAIN_TEST=1`. Availability tests inject a key lookup. Every
commit follows the required full Swift test command; the final gate also runs
`swift build --disable-sandbox` and scans tracked/diff content for credential
leaks.
