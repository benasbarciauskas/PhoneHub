# PhoneHub — Native macOS App Design

_Date: 2026-06-19 · Status: approved_

## 1. Scope

PhoneHub is a native **SwiftUI macOS dashboard** for manually controlling the
owner's own iPhones and Android phones from one Mac. It discovers connected
devices, lets the user focus one device, launches that platform's native mirror
window, and docks the mirror into the PhoneHub stage rectangle.

**Out of scope:** PhoneHub does not capture pixels, embed live streams, forward
synthetic clicks, run anti-detection logic, rotate proxies/SIMs, or orchestrate
multi-account device farms.

## 2. Architecture

PhoneHub uses an orchestrated mirror-docking architecture:

- **Android:** launch `scrcpy -s <serial>` with `--window-borderless`,
  `--window-x`, `--window-y`, `--window-width`, `--window-height`, and
  `--window-title`, then let scrcpy own the live mirror and input path.
- **iOS:** activate iPhone Mirroring (`com.apple.ScreenContinuity`), find its
  running app/window, and set `kAXPositionAttribute` / `kAXSizeAttribute` via
  Accessibility to dock it into the stage.
- **PhoneHub:** remains the dashboard and coordinator. It handles discovery,
  focus, native mirror launch/stop, stage rectangle calculation, and degraded
  state messages.

## 3. Components

- **`PhoneHubApp`** — SwiftUI app entry, single hidden-titlebar window with
  sidebar and stage.
- **`DeviceStore`** (`@Observable`) — discovers Android via `adb devices -l` and
  iOS via `xcrun devicectl`, stores `[Device]`, and tracks `focusedDevice`.
- **`AndroidController`** — Android discovery only.
- **`ScrcpyController`** — validates serials, builds scrcpy argv, resolves
  `scrcpy`, launches it non-blocking, tracks one process per serial, and stops
  the previous process when focus changes.
- **`MirroringController`** — activates iPhone Mirroring and asks `WindowDock` to
  position its window.
- **`WindowDock`** — AppKit/AX helper for Accessibility trust, iPhone Mirroring
  discovery, and window positioning.
- **`Sidebar`** — device list and refresh control.
- **`Stage`** — computes the stage rectangle in global screen coordinates,
  converts it for AX/window placement, launches or docks the focused mirror, and
  shows placeholder text for empty, docking, not-ready, and degraded states.

## 4. Data Flow

`discover()` -> `DeviceStore.devices` -> sidebar rows. Selecting a row sets
`focusedDevice`. `Stage` stops the previously focused mirror, measures its
screen-space stage rectangle, then launches scrcpy for Android or iPhone
Mirroring for iOS and docks that window into the stage. If `scrcpy` is missing
or Accessibility is not granted, the stage shows a clear action message instead
of crashing.

Only the focused device has an active mirror window managed by PhoneHub.

## 5. Packaging

`build-app.sh` builds `PhoneHub.app` and signs it with a stable self-signed
identity named `PhoneHub Self-Signed` stored in
`phonehub-signing.keychain-db`. Stable signing is required because macOS
Accessibility grants are tied to the app's signing identity/code identity; ad-hoc
signing can force users to re-grant access after every rebuild.

The bundle id remains `com.benas.phonehub`.

## 6. Error Handling

- Missing `adb` affects Android discovery and is shown in the sidebar.
- Missing `scrcpy` is shown in the stage: `scrcpy not installed - brew install
  scrcpy`.
- Missing Accessibility trust prompts macOS and shows: `Enable Accessibility for
  PhoneHub in System Settings -> Privacy -> Accessibility`.
- Device disconnects refresh back to the first available device or empty state.

## 7. Testing

- **Unit:** discovery parsing, shell tool behavior, scrcpy argv construction, and
  invalid serial rejection.
- **Manual smoke:** build `PhoneHub.app`, grant Accessibility, connect an Android
  device with scrcpy installed, select it, and confirm the scrcpy window docks.
  Then select an iOS device and confirm iPhone Mirroring docks.
