# androir-mcp — Android automation MCP (mirroir port)

Date: 2026-06-24
Status: Approved design (sub-project A of "AI presets")

## Purpose

Give Android the same AI-automation surface mirroir gives iOS, so one
`claude -p` agent loop drives both platforms unchanged — only the attached MCP
differs (`mirroir` for iOS, `androir` for Android). Backed entirely by `adb` +
`uiautomator`; no native code, no upstream fork.

## Scope guardrail (inherited from PhoneHub)

Single owner, the owner's own devices. Build device control + screen reading +
replayable personal automation. Do NOT add anti-detection, humanization-for-
evasion, proxy/SIM rotation, or multi-account farm orchestration. If a tool
request drifts there, refuse.

## Where it lives

Inside the PhoneHub repo at `androir/` (its own Node package). One repo, ships
with the presets feature. Can be extracted to a standalone repo later if reused.

## Language / deps

- Node + TypeScript, `@modelcontextprotocol/sdk` (official), stdio transport.
- No runtime deps beyond the SDK; shells `adb` via `child_process` (argv array,
  never a shell string).
- Distributable via `node androir/dist/index.js` or an `npx`-style bin. claude
  attaches it through an MCP config entry.

## Tool surface (names mirror mirroir for symmetry)

All tools take an optional `serial` (defaults to the single connected device;
errors if ambiguous). Serial is validated against a strict charset
(`[A-Za-z0-9.:_-]`, len ≤ 128) before reaching any subprocess — mirror the rule
in `Sources/PhoneHubCore/Shell.swift:isValidSerial`.

| Tool | adb implementation | Returns |
|---|---|---|
| `list_targets` | `adb devices -l` | serials + model + state |
| `status` | `adb -s S get-state` | device/offline/unauthorized |
| `screenshot` | `adb -s S exec-out screencap -p` | PNG image content |
| `describe_screen` | `adb -s S exec-out uiautomator dump /dev/tty` (fallback: dump to `/sdcard` then `exec-out cat`) → parse XML | element list: text / content-desc / class / center tap (x,y) / bounds; plus optional screenshot |
| `tap` (x,y) | `adb -s S shell input tap X Y` | confirmation |
| `swipe` (x1,y1,x2,y2,dur_ms?) | `adb -s S shell input swipe X1 Y1 X2 Y2 DUR` | confirmation |
| `long_press` (x,y,dur_ms?) | `input swipe X Y X Y DUR` (same point) | confirmation |
| `type_text` (text) | `adb -s S shell input text '<escaped>'` (space→%s, escape shell metachars; for unicode fall back to per-char or an IME broadcast if needed) | confirmation |
| `press_key` (key) | `adb -s S shell input keyevent <KEYCODE>` — map names (home→3, back→4, enter→66, recents→187) | confirmation |
| `press_home` | `input keyevent 3` | confirmation |
| `press_back` | `input keyevent 4` | confirmation |
| `launch_app` (name or pkg) | resolve name→package (cache from `pm list packages` + label lookup; accept explicit `pkg`), then `monkey -p PKG -c android.intent.category.LAUNCHER 1` | confirmation |
| `open_url` (url) | `am start -a android.intent.action.VIEW -d '<url>'` | confirmation |

Coordinate system: device pixels (uiautomator bounds + `input` are both in
device px), so `describe_screen` tap coords feed straight into `tap`. Document
this; no point-vs-pixel translation like iOS needs.

### describe_screen detail

`uiautomator dump` yields XML with `bounds="[x1,y1][x2,y2]"`, `text`,
`content-desc`, `class`, `clickable`, `package`. Parse to a flat list, compute
each node's center `((x1+x2)/2, (y1+y2)/2)` as its tap point, keep only nodes
with text/desc or `clickable=true` (drop pure layout containers), and emit a
compact text listing identical in spirit to mirroir's
`"<label>" at (x,y)`. This is more reliable than OCR — exact bounds, real text.

## Boundaries / validation

- Every serial + every interpolated value validated/escaped before `adb`.
- `adb` resolved on PATH (`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`) —
  GUI-launched agents don't inherit a login PATH. Surface a clear "adb not
  found" error.
- Per-call timeout (default 30s) with process-group kill on timeout.
- No secrets logged. Errors are concise, no stack traces to the model.

## Testing

A `demo`/self-check (`node androir/dist/selfcheck.js` or `npm test`) that, with
one Android connected:
1. `list_targets` returns ≥1 device.
2. `screenshot` returns non-empty PNG bytes.
3. `describe_screen` returns ≥1 element with a valid center within screen
   bounds.
4. XML-parse unit test on a captured `uiautomator` sample (offline, no device)
   asserting bounds→center math and label extraction.

The XML parser is the one piece of real logic — it gets a device-free unit test
with a fixture. adb-shelling tools are thin and verified by the live self-check.

## Out of scope (v1)

- Recording/replay skills (mirroir has these; add later if presets need them).
- Multi-device parallel control (one serial per call).
- Emulator-specific paths.
