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

## Setup

### 1. Install the device CLI tools (macOS, via Homebrew)

```bash
brew install libimobiledevice scrcpy android-platform-tools
```

- `libimobiledevice` provides `idevice_id`, `ideviceinfo`, and `idevicescreenshot` (iOS).
- `android-platform-tools` provides `adb` (Android).
- `scrcpy` mirrors an Android device's screen.

PhoneHub degrades gracefully if any of these are missing — that platform simply
shows no devices instead of crashing.

> iOS notes: `idevicescreenshot` needs a mounted developer disk image. Apple's
> native **iPhone Mirroring** app (used by Focus on iOS) supports only one
> mirrored iPhone at a time.

### 2. Install the Python dependencies

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Run the dashboard

```bash
python main.py
```

A window opens with a tile per connected device (model / OS / platform / short
serial / status). **Refresh** re-runs discovery; each tile's **Focus** mirrors
the device (iPhone Mirroring for iOS, `scrcpy` for Android) and **Screenshot**
saves a PNG under `screenshots/`.

### 4. Run the tests

```bash
pytest
```

The tests cover the device-discovery output parsing (`idevice_id` / `ideviceinfo`
and `adb devices -l`) with mocked subprocess output — no real devices needed.
