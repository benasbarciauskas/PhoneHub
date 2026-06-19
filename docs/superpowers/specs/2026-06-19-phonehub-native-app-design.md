# PhoneHub — Native macOS App Design

_Date: 2026-06-19 · Status: approved_

## 1. Scope

PhoneHub is a native **SwiftUI macOS app**: a command-center dashboard to
**manually** control the owner's own iPhones and Android phones from one Mac —
discover connected devices, view the focused device's live screen, and
click-to-tap / swipe / type on it.

**Out of scope (hard guardrail):** no automation, no anti-detection /
"humanization for evasion", no proxy/SIM rotation, no multi-account-per-device
farm orchestration. Single user, owner's own devices and accounts only. The
shipped Python tkinter MVP is **retired** in favour of this native app.

## 2. Architecture

Control backend = **WebDriverAgent (iOS)** + **scrcpy/adb (Android)** driven
directly (Approach 2 — "Appium-lite"). No Appium server / device-farm
orchestration layer (built for parallel test allocation, which we don't need).
WDA and scrcpy are the same engines a device farm wraps; PhoneHub talks to them
directly for lowest latency.

### Components

- **`PhoneHubApp`** — SwiftUI app entry, single window (sidebar + stage).
- **`DeviceStore`** (`@Observable`) — runs discovery (shells `idevice_id` /
  `ideviceinfo` for iOS, `adb devices -l` + `getprop` for Android), holds
  `[Device]`, supports manual refresh and periodic per-device sidebar snapshots.
- **`Device`** — `platform` (ios/android), `udid`, `model`, `osVersion`,
  `status`, `focused`.
- **`WDAClient`** (iOS) — launches/owns a WebDriverAgent session per iPhone
  (port-per-device), exposes the MJPEG stream URL and REST endpoints for
  tap / swipe / type / home / `/status`.
- **`AndroidController`** — `adb`/`scrcpy`; live frames via `adb exec-out
  screencap` polling, input via `adb shell input tap/swipe/text`.
- **`StreamView`** — decodes the MJPEG / frame source into `NSImage`, renders in
  SwiftUI, maps a click in the view to device coordinates and dispatches a tap.
- **`Sidebar`** — scrollable device rows (status dot · model · mode · snapshot).
- **`Stage`** — focused device live screen + control rail (home / back /
  screenshot / open-in-mirror).

## 3. Data flow

`discover()` → `DeviceStore.[Device]` → sidebar rows. Select a device → focus →
start stream (WDA MJPEG for iOS, screencap poll for Android) → `StreamView`
renders frames → user clicks → coordinate map → WDA/adb tap → device reacts →
next frame shows the result.

Only the **focused** device streams live (Command-center layout, 5–10 devices
target). Sidebar rows show an occasional still snapshot, not a live stream — so
there is at most one active stream at a time and performance scales to 10+.

## 4. Coordinate mapping (the tricky bit)

`StreamView` knows the displayed-image rect (with aspect-fit letterboxing) and
the device native resolution (WDA window size, or `adb wm size`). On click:
strip the letterbox offset, scale view-point → device pixels, send tap. This is
a **pure function** `viewPointToDevicePoint(click, viewRect, imageRect,
deviceSize)` and is unit-tested (letterbox on both axes, edge points, rounding).

## 5. iOS WebDriverAgent setup

One-time per iPhone: build + sign WebDriverAgent via Xcode (a free Apple ID
works; 7-day re-sign). On focus, PhoneHub launches WDA for that device, polls
`/status` until ready, then opens the MJPEG stream. Android needs only
`adb`/`scrcpy` — no signing. The iOS path is **deferred past the first slice**.

## 6. Vertical slice (first build)

Prove the full pipe end-to-end on **one Android device** (no WDA signing needed):

1. App launches → `DeviceStore` discovers connected devices → sidebar lists them,
   rendered with the OLED design-system tokens.
2. Select an Android → Stage shows its live screen (screencap poll).
3. Click on the stage → `adb shell input tap` at mapped coords → device reacts,
   visible in the next frame.
4. Screenshot button saves a PNG.

**Deferred:** iOS / WDA, sidebar live snapshots, full control rail, motion
polish, multi-device niceties.

## 7. Design system

A `Theme` enum + SwiftUI view modifiers encode the **OLED Black** palette and
the design judgment from the owner's design skills (taste, ui-ux-pro-max SwiftUI
track, Emil Kowalski motion, impeccable/polish finishing).

Tokens: bg `#000000`, surface `#0b0b0d`, elevated `#1c1c1f`, border `#1c1c1f`,
text `#f5f5f7`, subtext `#8a8a8e`, accent `#0a84ff`, status green / amber / red.
4-pt spacing grid, defined type scale, corner radii. Motion = fast, purposeful
springs (focus transition, sidebar selection) per Emil's philosophy — no gratuitous
animation. A `polish` / `impeccable` finishing pass runs before ship.

## 8. Packaging

Matches the owner's sibling Mac apps (Mirror Deck, MacCare): XcodeGen project +
`build-app.sh`, ad-hoc code-signed, installs to `/Applications`. **No
Accessibility grant** required (control is via WDA/adb, not the AX API). Locates
`adb` / `scrcpy` / `libimobiledevice` on the Homebrew paths and shows guidance if
a tool is missing.

## 9. Error handling

- Missing CLI tool (`adb`/`idevice_id`/`scrcpy`) → clear in-app banner with the
  `brew install` hint; never crash.
- Device disconnect → its row goes stale/red, any active stream stops cleanly.
- WDA fails to launch → actionable error surfaced in the stage area.
- Discovery never throws on a missing/zero-exit tool — degrades to empty.

## 10. Testing

- **Unit:** coordinate-mapping math; MJPEG frame parser; device-discovery output
  parsing.
- **UI:** manual smoke — run the app, confirm discovery + live frame + tap on a
  real Android.

## 11. Repo / process

Retire the Python MVP (`src/` tkinter + discovery, `main.py`, `requirements.txt`,
`tests/`). Build the native app in worktree `feat/native-foundation`. Ship the
vertical slice once review is clean + smoke-tested + CI green, then iterate
(iOS/WDA is the next phase).
