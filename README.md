# PhoneHub

Personal multi-device control + mirroring dashboard. Discover, view, and drive
**your own** connected iPhones and Android phones from one Mac app.

## Scope

- **Device list**: discover connected devices (`idevice_id` for iOS, `adb devices`
  for Android), show model / OS version / UDID-serial / status.
- **Live monitoring**: periodic / on-demand screenshots, health indicators, logs.
- **Mirroring focus**: click a device → bring its iPhone Mirroring window forward
  (AppleScript) or launch `scrcpy` for Android.
- **Manual ↔ scripted toggle**: pause/resume a per-device Appium session so you can
  hand off between manual use and your own automation scripts.
- **Scripting**: Appium-driven taps / scrolls / launch-app for your own testing and
  personal automation.

## Out of scope

Not an account farm. No anti-detection / "humanization-for-evasion" engine, no
proxy/SIM rotation, no multi-account-per-device orchestration aimed at evading
platform integrity systems. Single user, single owner's devices and accounts,
official automation surfaces only.

## Stack

Python 3.11+ · Appium 2.x (XCUITest / UiAutomator2) · customtkinter ·
`libimobiledevice` (iOS discovery) · `adb` + `scrcpy` (Android).

## Build & run

Requires macOS 14+, Swift toolchain (Command Line Tools or Xcode), and
`android-platform-tools` for Android control:

```bash
brew install android-platform-tools   # provides adb
./build-app.sh                         # builds PhoneHub.app
open PhoneHub.app
```

Connect an Android phone with USB debugging enabled and authorize the Mac.
The device appears in the sidebar; click it to see and control its live screen.

iOS support (WebDriverAgent) is a later phase.

## Tests

```bash
swift test
```
