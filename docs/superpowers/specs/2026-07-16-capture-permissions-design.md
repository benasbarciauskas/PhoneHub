# Capture Permissions and Policy Design

## Goal

Add live macOS permission controls to the existing settings sheet and make all agent-initiated screen capture obey one persisted user policy.

## Scope

The settings sheet gains a Permissions section with live Accessibility and Screen Recording status, request buttons, exact System Settings deep links, and the supplied explanations of capture scope. Status refreshes when a window becomes key and every two seconds only while the sheet is mounted.

`screenCapturePolicy` has three persisted values:

- `duringRunsOnly` (default): capture tools are allowed only while a preset run, chat turn, or automation run is active.
- `disabled`: `screenshot`, `start_recording`, and `stop_recording` are denied. Vision-enabled API runs use `describe_screen` without an image, and each affected run or turn gets one clear log notice.
- `always`: capture tools are unrestricted, matching current behavior.

Android capture remains device-local through adb. Screen Recording permission is relevant to iOS because mirroir captures only the iPhone Mirroring window.

## Architecture

`PhoneHubCore` owns a Codable `ScreenCapturePolicy` and one pure gate function. The function accepts the policy plus whether execution is active and returns a decision containing whether capture is allowed and the affected MCP tool names. Unit tests cover every policy/activity combination.

`AutomationPlan` carries that decision so both CLI backends enforce the same result:

- Claude receives `--disallowedTools` entries for the three fully qualified MCP tools when capture is denied.
- Codex receives `mcp_servers.<server>.disabled_tools=[...]` in its per-run configuration.
- The system preamble explicitly directs the agent to use `describe_screen` when capture is denied.

API backends use the same plan decision in `ApiAgentRuntime`. When vision is enabled and capture is denied, the runtime skips `screenshot`, calls only `describe_screen`, and sends the resulting text without image content.

The app engines resolve the persisted policy as each run or chat turn starts. They append one notice to the visible run/chat log when the plan denies capture. Existing direct automation probing already uses only `describe_screen`, so it needs no capture-tool branch.

## Persistence and UI

`LLMAppConfig` stores the enum using the existing Codable/UserDefaults pattern. Missing legacy values decode as `duringRunsOnly`. `LLMSettingsModel` exposes the current policy and persists picker changes.

The existing sheet remains structurally intact. A scroll view and compact Permissions section avoid a larger tab refactor. A focused app-side helper wraps the AppKit/CoreGraphics/ApplicationServices permission APIs and System Settings URLs; no macOS framework enters `PhoneHubCore`.

## Alternatives Considered

1. Client-side plan filtering (chosen): works for mirroir and androir, keeps one Core decision, and avoids another process.
2. mirroir permission files: rejected because they do not cover androir and project/global file precedence would couple runs to external state.
3. A local MCP proxy: rejected as unnecessary process and protocol complexity when both supported CLI clients expose deny-list configuration.

## Error Handling

Permission request APIs may leave status unchanged; the UI simply refreshes and continues polling. Invalid deep-link URLs produce no action. Existing settings persistence errors continue through `LLMSettingsModel.statusMessage`.

Capture denial is not a run failure. The agent receives text-only screen descriptions and the user sees the denial notice once per run or turn.

## Testing

- Pure gate tests cover all policies with active and inactive execution.
- Config tests cover default, Codable round-trip, and legacy fallback.
- Plan tests cover Claude and Codex deny arguments for iOS and Android, plus allowed active/default behavior.
- API runtime tests prove denied vision never calls `screenshot`, `start_recording`, or `stop_recording`, calls `describe_screen`, and attaches no image.
- Settings-model tests prove picker persistence.
- Existing full Swift tests and the required Swift build command remain green.
