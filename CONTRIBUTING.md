# Contributing to PhoneHub

Thanks for your interest in improving PhoneHub. This guide covers how to set up,
build, test, and submit changes.

## Scope

PhoneHub is a **personal** multi-device control and mirroring dashboard for the
owner's **own** iPhones and Android phones, driven from one Mac: discovery,
mirroring/docking, focus and wall layouts, and personal automation presets.

It deliberately does **not** include — and will not accept contributions that
add — anti-detection / detection-evasion logic, a "humanization engine" framed
for avoidance, proxy/SIM rotation, or multi-account-per-device farm
orchestration aimed at evading platform integrity systems. If a change drifts
toward that, it's out of scope.

## Prerequisites

- **macOS 14+** with Swift / Xcode (or Command Line Tools) installed.
- **`adb` + `scrcpy`** (`brew install android-platform-tools scrcpy`) to exercise
  Android mirroring/automation.
- An iPhone supported by Apple's **iPhone Mirroring**, and/or an Android phone
  with **USB debugging** enabled, if you want to test docking end-to-end.
- Optional automation deps: [mirroir](https://github.com/jfarcand/mirroir-mcp)
  (iOS), [androir](https://github.com/benasbarciauskas/androir-mcp) (Android),
  and the `claude` CLI.

## Setup

```bash
git clone https://github.com/benasbarciauskas/PhoneHub.git
cd PhoneHub
```

## Build & test

```bash
# Build + assemble + sign the app (stable self-signed identity)
./build-app.sh
open PhoneHub.app

# Run the test suite (matches CI)
CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --disable-sandbox
```

Always run `swift build --disable-sandbox` and `swift test --disable-sandbox`
before opening a PR — CI runs the same on `macos-latest` for every pull request
and on pushes to `main`.

## Branch & PR flow

This repo follows the **Ruflo Git Standard** (`scripts/flow.sh`):

- `main` is live. Feature branches are `<type>/<slug>`, where `type` is one of
  `feat | fix | chore | refactor | docs` (e.g. `feat/wall-grid`).
- `scripts/flow.sh feature "<name>"` creates an isolated worktree under
  `.worktrees/<slug>` on a fresh `feat/<slug>` branch. A sub-agent or contributor
  works **only** inside that worktree — never touching `main`, other worktrees,
  or another feature's files.
- `scripts/flow.sh done` pushes the branch and opens a PR into the right base.
- `main` is protected by a GitHub ruleset: no direct pushes, PR + green CI
  required, squash-only merges, head branch auto-deletes on merge.
- Never push directly to `main`, never `--no-verify`, never merge your own PR
  without review.

Fill in the PR template (summary, what changed, testing done, checklist).

## Code conventions

- **Source layout:** code in `src/` / `Sources/`, tests in `Tests/`, scripts in
  `scripts/`. Keep files under ~500 lines.
- **Validate at boundaries.** UDIDs, device serials, and any shell arguments to
  `idevice*` / `adb` / `scrcpy` must be validated and passed as argv arrays —
  never interpolated into a shell string.
- **No secrets.** Never commit `.env` files, tokens, keys, or `*.session.json`.
  A pre-commit hook blocks this; do not `--no-verify` around it.
- **No secrets or PII in logs.** Keep run-log output and error messages free of
  credentials, tokens, and private data.
- **Treat AI input as untrusted.** Preset goal text and agent output are
  untrusted; automation gets the same authorization as the user. See
  [SECURITY.md](SECURITY.md) for the full baseline.

By contributing, you agree your contributions are licensed under the project's
[Apache-2.0](LICENSE) license.
