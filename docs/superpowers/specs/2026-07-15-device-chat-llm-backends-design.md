# Device Chat, Pluggable LLM Backends, Skills Setup — Design

**Date:** 2026-07-15
**Status:** Approved (design), pending spec review

## Problem

PhoneHub's AI presets already spawn `claude -p` wired to mirroir (iOS) / androir
(Android) MCP servers, but:

1. There is no way to **converse** with the agent — you fire a preset goal and
   watch a log. Users want a chat: "what's on screen?" → answer → "tap
   Settings" → it acts.
2. The LLM backend is **hardcoded to `claude`**. Users may have Codex instead.
3. The mirroir **skills repo** (`~/.mirroir-mcp/skills` — app knowledge,
   popup/obstacle patterns that make screen-driving reliable) is never
   installed or updated by anything in this repo.
4. The preset loop has **never been verified end-to-end** against a real
   device.
5. A missing/logged-out CLI fails cryptically at spawn time.

Non-goal: PhoneHub never ships or stores an API key. It shells the **host
user's own** `claude` / `codex` CLI login. (Already true; this spec keeps it
that way and makes it visible.)

## 1. Device Chat

A chat panel bound to the **focused device**, in the sidebar area alongside
presets.

**Engine.** Reuses the existing `AutomationEngine` plumbing:

- First user message → spawn agent exactly like an adhoc preset run
  (`claude -p --output-format stream-json --mcp-config <temp> --allowedTools
  mcp__<server>__* --permission-mode default`), with a chat-flavored system
  prompt: "You are operating <device>. Converse with the user; use the MCP
  tools to look at and drive the screen when asked. Ask when unsure."
- Each subsequent user message → `claude --resume <sessionId>` (same
  mechanism as today's `NEED_INPUT` resume path).
- One chat session per device; sticky until the user taps **New chat**.
- **Stop** button kills the in-flight process (existing behavior), chat
  session survives (next message resumes).

**UI.** Transcript view: user/assistant bubbles; tool calls rendered as
collapsed one-line entries (e.g. `▸ tap(…)`) expandable to args; streaming
assistant text appears live. Input field pinned at bottom, disabled while a
turn is in flight (Stop always enabled). "New chat" clears the transcript and
drops the session id.

**Concurrency.** A chat turn and a preset run on the same device are mutually
exclusive (single `AutomationEngine` run slot per device — same rule as
today). Different devices independent, as today.

**Persistence.** Chats persist per macOS user account under
`~/Library/Application Support/PhoneHub/chats/<deviceId>.json`:
transcript entries (role, text, tool summaries, timestamps) + last
`sessionId` + backend used. Loaded on app start; a stale `sessionId` that the
CLI refuses to resume degrades gracefully (new session started, transcript
kept). Same store pattern as `PresetStore` (`presets.json`).

## 2. Pluggable backends (`AgentBackend`)

```swift
enum AgentBackend: String, Codable { case claude, codex }
```

- `AutomationPlan` gains a backend field; per-backend arg builder:
  - **claude** (default): current args, unchanged.
  - **codex**: `codex exec --json -c mcp_servers.<name>.command=… -c
    mcp_servers.<name>.args=… --skip-git-repo-check`, resume via
    `codex exec resume <sessionId>`. Exact flags validated during
    implementation against the installed codex CLI.
- Per-backend **stream parser**: existing `StreamJSONParser` stays
  claude-specific; a `CodexStreamParser` maps codex JSONL events into the same
  internal event enum (assistant text, tool call, session id, result,
  NEED_INPUT equivalent). Both feed the same log/chat models.
- **Picker**: app-level default backend in a small settings surface +
  per-preset override; chat uses the app default.
- **Availability detection**: on launch (and before each run) resolve the
  backend binary via `PATH` lookup; if missing or unauthenticated, runs and
  chat show a friendly actionable message ("Install the claude CLI and run
  `claude` once to log in") instead of a spawn error. PhoneHub never stores
  keys — auth belongs to the host CLI.
- Phase 2: codex ships **after** chat works on claude. If codex resume/MCP
  flags prove unstable, codex ships without resume (each chat message includes
  rolled-up context) — degradation noted in UI as "codex: stateless mode".

## 3. Skills repos setup

`scripts/setup-skills.sh`:

- Clone or `git pull` `https://github.com/jfarcand/mirroir-skills` →
  `~/.mirroir-mcp/skills`.
- Androir equivalent: check for a published androir skills repo; if none
  exists, print "no androir skills repo yet" and exit 0 (don't fail).
- Idempotent, re-runnable, no sudo.

App side: presets panel shows a passive status line — "iOS skills: installed ✓
/ not installed (run scripts/setup-skills.sh)" — detected by directory
existence. No in-app git operations.

## 4. End-to-end verification (gate)

Never tested against real hardware. Before this feature branch merges:

- Run one real preset + one chat exchange against a real iOS device (mirroir
  confirmed working on this host) — screen described, one action performed.
- Android: verify `npx -y androir-mcp` actually resolves on npm. If
  unpublished, Android automation paths show "androir-mcp not available yet"
  and the e2e gate covers iOS only (documented in README).
- These are manual gates recorded in the PR description, plus unit tests for:
  arg building per backend, codex event parsing (fixture JSONL), chat
  persistence round-trip, availability detection fallback messaging.

## Error handling

- Spawn failure / non-zero exit → surfaced in chat as a system bubble with
  stderr tail (existing error-dialog pattern from PhoneDrop applies: errors
  are shown, not swallowed).
- Resume failure → transparent new-session retry once, then system bubble.
- MCP server death mid-turn → turn ends with error bubble; next message
  starts fresh turn.

## Testing

`swift test` additions: plan/arg-builder tests per backend, codex parser
fixtures, chat store round-trip, stale-session fallback. Manual e2e gate as
above.

## README

New "Device Chat" section + "bring your own LLM" note (uses your local
claude/codex login; PhoneHub stores no credentials) + skills setup
instructions.
