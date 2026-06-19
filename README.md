# PhoneHub

Personal multi-device mirroring dashboard for your own connected iPhones and
Android phones from one Mac app.

## Architecture

PhoneHub orchestrates native mirror windows. It does not capture pixels, embed
streams, or forward synthetic clicks.

- Android: launches `scrcpy -s <serial>` borderless and positions the window into
  the PhoneHub stage with scrcpy window flags.
- iOS: opens Apple's iPhone Mirroring app (`com.apple.ScreenContinuity`), finds
  its window, and docks it into the stage using the macOS Accessibility API.
- PhoneHub is the dashboard: discovery, focus selection, launch, and window
  placement live in the app; touch input remains inside the native mirror apps.

## Requirements

- macOS 14+ and Swift/Xcode tooling.
- Android: `brew install android-platform-tools scrcpy`.
- iOS docking: grant PhoneHub Accessibility in System Settings -> Privacy &
  Security -> Accessibility.
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

## Tests

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --disable-sandbox
```
