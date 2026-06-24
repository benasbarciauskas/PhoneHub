# PhoneHub AI Presets

Date: 2026-06-24
Status: Approved design (sub-project B of "AI presets")
Depends on: `androir-mcp` (sub-project A) for the Android backend.

## Purpose

Add named, AI-driven automation presets to PhoneHub. A preset is a plain-English
goal ("Warm up TikTok: scroll 5 videos, dwell 1–5s each"). Running it spawns a
headless `claude -p` wired to the right MCP for the focused device's platform
(`mirroir` for iOS, `androir` for Android); Claude sees the screen, decides, and
acts toward the goal — recovering from popups/ads — while PhoneHub streams its
progress. A visible Stop ends it.

## Scope guardrail (repo CLAUDE.md — enforced)

Personal automation of the owner's own devices only. No anti-detection,
humanization-for-evasion, proxy/SIM rotation, or multi-account farming. Preset
goal text and the engine's system prompt must not frame automation as evading
platform integrity systems. If a preset drifts there, refuse to run it.

## Components

### 1. `Preset` model + `PresetStore` (PhoneHubCore)
```
struct Preset: Codable, Identifiable {
    var id: UUID
    var name: String
    var goal: String            // plain-English instruction
    var app: String?            // optional app to ensure open first
    var platforms: [Platform]   // [.ios], [.android], or both
    var maxSteps: Int           // hard cap on agent actions (default e.g. 40)
}
```
- `PresetStore` (@Observable): loads/saves `presets.json` in
  `~/Library/Application Support/PhoneHub/`. Seeds a couple of built-ins on first
  run (e.g. "Warm up TikTok", "Open Instagram"). CRUD: add / edit / delete.
- Atomic write (temp file + rename). Validate on load; ignore/quarantine
  malformed entries rather than crash.

### 2. `AutomationEngine` (PhoneHub app, @Observable, @MainActor)
- `run(preset:on device:)`:
  - Refuse if preset platforms don't include the device platform.
  - Build the prompt: a fixed system preamble (role, the scope guardrail, "use
    only the attached phone-control tools, stop when the goal is met or maxSteps
    reached, dwell naturally") + the preset goal + device context (platform,
    serial for Android).
  - Build args: `claude -p "<goal>" --output-format stream-json
    --mcp-config <generated json> --allowedTools <mirroir|androir tools>
    --max-turns <maxSteps>`. (Exact flags verified against `claude --help`
    during implementation — see Risks.)
  - iOS: mcp-config points at `mirroir` (the existing global server). Android:
    points at `androir` (`node androir/dist/index.js`), passing the device
    serial via env or a tool arg.
  - Spawn with the existing `runTool` machinery, extended to **stream** stdout
    line-by-line instead of buffering to completion. Parse stream-json events →
    append to a live log + current-status line.
  - `stop()`: terminate the process group (SIGTERM→SIGKILL), like Shell.swift's
    timeout path.
- Publishes: `state` (idle / running / stopped / finished / failed),
  `log: [String]`, `currentAction: String?`, `runningPreset: Preset?`.
- Single active run at a time (one focused device, one mirror). Guard against
  concurrent runs.

### 3. UI — `PresetsPanel.swift` (PhoneHub)
- New panel listing presets that match the focused device's platform.
- Each row: name + Run button (disabled if no focused device / wrong platform /
  a run is active). `+` opens an add/edit sheet (name, goal, app, platforms,
  maxSteps).
- While running: show `currentAction`, a scrollable log, and a Stop button.
- Placement: a section in the Sidebar below the device list (keeps Stage focused
  on the mirror). If it crowds the Sidebar, use a segmented Sidebar (Devices /
  Presets) — decide during implementation from how it looks.

## Data flow

```
User clicks Run on Preset P (focused device D)
  → AutomationEngine.run(P, D)
     → builds prompt + mcp-config for D.platform
     → spawns: claude -p ... (stream-json)
        → claude: [screenshot → describe → decide → tap/swipe]* via mirroir/androir
        → emits stream-json events
     → engine parses events → log / currentAction (live in UI)
  → goal met or maxSteps → claude exits → state = finished
  User clicks Stop → engine kills process group → state = stopped
```

## Security / safety

- `claude -p` runs with `--allowedTools` limited to the phone-control MCP tools
  (+ the minimum it needs), NOT a blanket allow — so the spawned agent can only
  drive the phone, not the Mac. No `--dangerously-skip-permissions` on this
  spawn; preflight the allowlist instead.
- maxSteps / `--max-turns` cap bounds runaway loops and token spend.
- Serial validated before reaching androir/adb (reuse `isValidSerial`).
- No secrets in prompts, logs, or the stream view. Errors shown concisely.
- The scope guardrail is part of the system preamble AND enforced at the UI
  (no farm/rotation preset templates shipped).

## Testing / verification

- `PresetStore`: round-trip encode/decode, atomic-save, malformed-file
  tolerance (unit tests, no device).
- `AutomationEngine`: prompt/args builder is a pure function → unit-test that
  iOS routes to mirroir, Android to androir, platform-mismatch is refused, and
  maxSteps maps to `--max-turns`. Stream-json parser tested against captured
  sample events (offline fixture).
- End-to-end (manual, real device, build-loop verification gate): run "Open
  Instagram" on the iPhone and on an Android, watch the live log, confirm the
  app opens; run "Warm up TikTok", confirm it scrolls and recovers from an ad;
  confirm Stop halts mid-run.

## Risks / to verify during implementation

- Exact `claude -p` flags for headless MCP attach + streaming + tool allowlist
  (`--mcp-config`, `--output-format stream-json`, `--allowedTools`,
  `--max-turns`) — verify against the installed `claude --help` before wiring;
  adjust names if they differ. This is the one external-contract unknown.
- `androir` serial passing (env vs per-tool arg) — settle when A is built.
- Sidebar real-estate — may need the segmented approach.

## Out of scope (v1)

- Scheduling / recurring runs.
- Multi-device fan-out (run one preset across several phones at once).
- Per-step screenshot thumbnails in the log (text log only for v1).
- Editing/recording presets as deterministic scripts (AI-goal only).
