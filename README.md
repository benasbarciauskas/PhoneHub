<p align="center">
    <img src="assets/logo.svg" width="96" height="96" alt="PhoneHub logo">
</p>
<h1 align="center">PhoneHub</h1>
<p align="center"><strong>Mirror, chat with, and automate your iPhones and Android phones from one Mac</strong></p>
<div align="center">
    <a href="https://github.com/benasbarciauskas/PhoneHub/actions/workflows/ci.yml" target="_blank">
    <img alt="CI" src="https://github.com/benasbarciauskas/PhoneHub/actions/workflows/ci.yml/badge.svg"></a>
    <a href="LICENSE" target="_blank">
    <img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square"></a>
    <img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple&logoColor=white">
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white">
</div>

## Features

- **Multi-device discovery**: every connected iPhone and Android phone in one sidebar, with live state and model info
- **Native mirroring**: docks each device's real mirror window into a managed stage — Apple's iPhone Mirroring for iOS, borderless `scrcpy` for Android
- **Focus & wall layouts**: watch one phone full-stage, or tile several side by side
- **AI presets**: name a plain-English goal and a headless agent reads the screen, taps, swipes, and types its way there, recovering from popups
- **Device chat**: converse with an agent bound to the focused device — ask what's on screen, request actions, keep going back and forth; transcripts persist per device
- **Bring your own LLM**: choose Claude or Codex; PhoneHub shells out to your local CLI login and never stores or reads API keys or credentials
- **Local only**: talks exclusively to the phones your Mac already sees; nothing leaves your machine

## Getting Started

Requirements:

- macOS 14+ with Swift / Xcode (or Command Line Tools)
- Android: `brew install android-platform-tools scrcpy`
- iOS docking: grant PhoneHub **Accessibility** (System Settings → Privacy & Security → Accessibility)
- Automation & chat (optional): the `claude` or `codex` CLI, logged in — agents run through [mirroir](https://github.com/jfarcand/mirroir-mcp) (iOS) and [androir](https://github.com/benasbarciauskas/androir-mcp) (Android) MCP servers, fetched automatically via `npx`

Build and run:

```bash
./build-app.sh
open PhoneHub.app
```

`build-app.sh` builds the release binary, assembles `PhoneHub.app`, and signs it with a stable self-signed identity so the Accessibility grant survives rebuilds.

## Install from a release

Download the latest `PhoneHub-<version>-macos.zip` from [GitHub Releases](https://github.com/benasbarciauskas/PhoneHub/releases), unzip it, and move `PhoneHub.app` to `/Applications`.

On first launch, right-click `PhoneHub.app` and choose **Open**. The Gatekeeper warning is expected because the app is self-signed rather than signed and notarized with an Apple Developer ID.

Optionally verify the download against the SHA-256 checksum published with the release:

```bash
shasum -a 256 PhoneHub-<version>-macos.zip
```

## Releasing

Maintainers run `scripts/release.sh <version>`, then run the `gh release create` command it prints.

Install or update the iOS automation skills mirroir uses (app knowledge, popup and obstacle patterns — improves agent reliability):

```bash
scripts/setup-skills.sh
```

Run tests:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --disable-sandbox
```

## AI Presets

A preset is a named, plain-English goal — for example *"Open Settings, go to Wi-Fi, and tell me which network is connected."* Running one spawns a headless agent wired to the focused device's phone-control MCP server. It loops: read the screen, decide, act, repeat — streaming progress into a live log with a Stop button. If the agent hits a blocker (login wall, ambiguous choice), it pauses and asks; your answer resumes the same session.

## Device Chat

Switch the sidebar from **Presets** to **Chat** and talk to an agent bound to the focused device:

> *"What's on screen right now?"* → description → *"Open Settings and check which Wi-Fi network is connected"* → it acts and reports back.

Every message continues the same agent session, so context carries across turns. History is stored per device under `~/Library/Application Support/PhoneHub/chats/` and restored on launch. A chat turn and a preset run are mutually exclusive — one agent controls a phone at a time. **Stop** ends the current turn; **New chat** starts fresh.

Choose Claude or Codex from the sidebar gear menu. Presets can inherit that app default or override it in the preset editor; chat always uses the app default. Changing backends keeps the transcript but starts a fresh CLI session on the next message because sessions cannot transfer between backends.

PhoneHub has no credential store and brings no API key: it uses whichever local `claude` or `codex` CLI login you selected.

## PhoneDrop

A drag-to-phone Dock droplet: drop photos onto the PhoneDrop icon and they land in your Android phone's gallery — EXIF/GPS stripped from a copy first, pushed over `adb` via Tailscale (USB fallback), no tap needed on the phone.

```bash
scripts/phonedrop.sh install   # one-time setup (asks for the phone's Tailscale hostname)
```

Then drag `~/Applications/PhoneDrop.app` to your Dock. After a phone reboot, the bundled auto-arm LaunchAgent re-enables wireless adb when the phone is plugged in via USB. Useful commands: `status`, `connect`, `rearm`, `check`, `push <files>` — see `scripts/phonedrop.sh`. Tests: `bash tests/phonedrop_test.sh` (no phone required).

One-time phone setup: install Tailscale (always-on VPN, battery-optimization excluded), enable Wireless debugging, pair once with the Mac, and run `adb tcpip 5555`.

## Roadmap

- [x] Multi-device discovery (iOS + Android)
- [x] Native mirroring and docking, focus and wall layouts
- [x] AI presets with live log, Stop, and interactive resume
- [x] Per-device chat with streaming replies and persisted transcripts
- [x] Codex backend (`codex` CLI) as an alternative to `claude`
- [ ] Per-device preset-run history
- [ ] Scheduling / recurring presets
- [ ] Richer wall layouts (custom grids, per-tile zoom)
- [ ] Packaged, notarized `.app` release

## License

[Apache-2.0](LICENSE)
