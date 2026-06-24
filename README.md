# PhoneHub

Multi-device mirroring and automation dashboard for connected iPhones and
Android phones, from one Mac app. Open source.

## Architecture

PhoneHub orchestrates native mirror windows and can drive them with AI
automation presets.

- Android: launches `scrcpy -s <serial>` borderless and positions the window into
  the PhoneHub stage with scrcpy window flags.
- iOS: opens Apple's iPhone Mirroring app (`com.apple.ScreenContinuity`), finds
  its window, and docks it into the stage using the macOS Accessibility API.
- Automation: presets run an AI agent that reads the screen and drives the
  device toward a goal — iOS via [mirroir](https://github.com/jfarcand/mirroir-mcp),
  Android via [androir](https://github.com/benasbarciauskas/androir-mcp)
  (adb / uiautomator).
- PhoneHub is the dashboard: discovery, focus selection, launch, window
  placement, and preset automation live in the app.

## Requirements

- macOS 14+ and Swift/Xcode tooling.
- Android: `brew install android-platform-tools scrcpy`.
- iOS docking: grant PhoneHub Accessibility in System Settings -> Privacy &
  Security -> Accessibility.
- Automation (optional): mirroir (iOS) and/or androir (Android) on the host,
  plus the `claude` CLI for the agent loop.
- Stable signing: `build-app.sh` creates and uses a persistent self-signed
  identity named `PhoneHub Self-Signed` in `phonehub-signing.keychain-db` so the
  Accessibility grant survives rebuilds.

## Build & Run

```bash
./build-app.sh
open PhoneHub.app
```

Connect Android devices with USB debugging enabled and authorized. Connect iOS
devices supported by Apple's iPhone Mirroring. Select a device in the sidebar to
launch and dock its native mirror window into the stage.

## Responsible use

Use PhoneHub on devices and accounts you are authorized to control, and follow
the terms of the apps you automate.

## Tests

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --disable-sandbox
```
