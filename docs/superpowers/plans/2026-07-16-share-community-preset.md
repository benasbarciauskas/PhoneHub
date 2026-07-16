# Share to Community Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export PhoneHub presets and automations into the community catalog format and submit them as GitHub pull requests from the app.

**Architecture:** Put deterministic mapping, validation, slugs, and path construction in PhoneHubCore. Keep the `gh` workflow in a main-actor-safe app controller using the existing argv-only process helper, then expose one reusable SwiftUI sheet from both list context menus.

**Tech Stack:** Swift 5.9, macOS 14, Foundation, SwiftUI, XCTest, GitHub CLI REST API.

## Global Constraints

- Work only in `feat/share-community-preset`; do not alter the catalog checkout or another worktree.
- Use no local clone, shell string, stored credential, new dependency, or AI attribution.
- Community JSON contains labels only: no IDs, coordinates, or `switchDevice`.
- Keep files below about 500 lines and pass the full supplied Swift test and build commands.

---

### Task 1: Pure community export

**Files:**
- Create: `Tests/PhoneHubCoreTests/CommunityPresetExportTests.swift`
- Create: `Sources/PhoneHubCore/CommunityPresetExport.swift`

**Interfaces:**
- Produces: `communityPresetJSON(name:platform:app:steps:)`, the `Preset` overload, `slug(_:)`, `communityPresetPath(platform:app:name:)`, and descriptive export errors.

- [ ] Write exact-output and validation tests for all step mappings, stripped fields, point labels, `switchDevice`, empty inputs/steps, schema constraints, slugs/paths, and AI goals.
- [ ] Run the filtered test target and confirm it fails because the export APIs do not exist.
- [ ] Implement ordered pretty JSON, validation, mapping, slugging, and path construction.
- [ ] Run filtered and full tests, then commit `feat: add community preset export`.

### Task 2: GitHub CLI submission controller

**Files:**
- Create: `Sources/PhoneHub/CommunityShareController.swift`

**Interfaces:**
- Consumes: validated JSON data/path plus display metadata and `runTool("gh", args)`.
- Produces: `@MainActor CommunityShareController.submit(...) async throws -> URL`.

- [ ] Resolve/authenticate `gh`, current login, and upstream collision before mutations.
- [ ] Fork non-owner accounts idempotently and resolve the target default branch HEAD.
- [ ] Create a unique branch, PUT base64 content, open the upstream-main PR, and return its URL.
- [ ] Normalize missing/auth/CLI/API errors without exposing credentials; pass every value as a separate argv item.
- [ ] Build and commit `feat: submit community presets with gh`.

### Task 3: Share sheet and row actions

**Files:**
- Create: `Sources/PhoneHub/CommunityShareSheet.swift`
- Modify: `Sources/PhoneHub/PresetsPanel.swift`
- Modify: `Sources/PhoneHub/AutomationsPanel.swift`

**Interfaces:**
- Consumes: a `Preset` or `Automation`, core live validation, and `CommunityShareController`.
- Produces: a 360-point share sheet launched by either row context menu.

- [ ] Add a shared item wrapper that maps AI goals and automation steps.
- [ ] Build the required name/platform/app fields, mapped-step list, labels-only note, and live inline validation.
- [ ] Add progress, inline API errors, clickable success URL, Submit/Cancel/Done behavior, and disable invalid submission.
- [ ] Wire `Share to Community…` into both context menus without changing run/edit behavior.
- [ ] Build, run the full tests, and commit `feat: add community sharing UI`.

### Task 4: Review and final verification

- [ ] Review `origin/main..HEAD` for schema drift, JSON stability, unsafe argv construction, GitHub fork/owner edge cases, actor violations, UI state issues, and files over 500 lines; fix every important finding test-first where logic changes.
- [ ] Run `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox`.
- [ ] Run `CLANG_MODULE_CACHE_PATH=$PWD/.build/cache/clang DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`.
- [ ] Verify the worktree is clean, commits are conventional, and author/committer are `Benas Barciauskas <benasbarciauskas@gmail.com>`.
