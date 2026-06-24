# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-24

### Added

- Native SwiftUI macOS app foundation: device-discovery dashboard with a sidebar,
  a managed stage, focus selection, screenshot, and a stable self-signed build
  (`build-app.sh`) so the Accessibility grant survives rebuilds.
- **Multi-device discovery** — enumerate connected iPhones (Apple iPhone
  Mirroring) **and** Android phones (`adb`) with live state and model info.
- **Native mirroring & docking** — open each device's real mirror window and dock
  it into the stage: iOS via iPhone Mirroring (`com.apple.ScreenContinuity`,
  positioned with the macOS Accessibility API) and Android via borderless
  `scrcpy -s <serial>` placed with scrcpy window flags.
- **Video-wall layout** — tile several mirror windows into a stage and watch them
  at once, alongside the single-device focus layout.
- **Mirror menu controls** — drive the docked mirror windows from the app.
- **Resync loop** — keep docked windows aligned in the stage as they move or
  resize.
- **AI automation presets** — name a plain-English goal and run it against the
  focused device; a headless `claude -p` agent wired to `mirroir` (iOS) /
  `androir` (Android) reads the screen and drives the device toward the goal,
  with a live run log and a Stop button.

[Unreleased]: https://github.com/benasbarciauskas/PhoneHub/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/benasbarciauskas/PhoneHub/releases/tag/v0.1.0
