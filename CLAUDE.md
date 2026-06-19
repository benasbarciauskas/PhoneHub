# PhoneHub

Personal multi-device control + mirroring dashboard for **the owner's own** iPhones
and Android phones, driven from one Mac. Python 3.11+ · Appium 2.x · customtkinter ·
`libimobiledevice` · `adb`/`scrcpy`.

## Scope guardrail (enforced)

Single user, single owner's devices and accounts. Build device discovery,
mirroring focus, manual↔scripted session toggle, monitoring, and personal
automation. **Do NOT** build: anti-detection / detection-evasion logic, a
"humanization engine" framed for avoidance, proxy/SIM rotation, or
multi-account-per-device farm orchestration aimed at evading platform integrity
systems. If a task drifts toward that, stop and surface it.

## Conventions

- Source in `src/`, tests in `tests/`, scripts in `scripts/`. Keep files under ~500 lines.
- Validate input at boundaries (UDIDs, shell args to `idevice*`/`adb`). Never shell-inject.
- Never commit secrets or `.env`.
- Sub-agents work ONLY in their own `.worktrees/<slug>` and commit there.

<!-- RUFLO-GIT-STANDARD -->
## Git Workflow (Ruflo Git Standard)

Branches: `main` = live. `beta` = integration/preview (where it exists). Feature branches are
`<type>/<slug>` where type ∈ `feat|fix|chore|refactor|docs`.

Flow (one verb — `scripts/flow.sh`):
- `scripts/flow.sh feature "<name>"` → new worktree under `.worktrees/<slug>` on `feat/<slug>`,
  branched off `beta` if it exists, else `main`. Account is auto-switched to the repo owner.
- A sub-agent works ONLY inside its assigned worktree on its `feat/` branch. It must not touch
  `main`/`beta`, other worktrees, or other features' files.
- `scripts/flow.sh done` → push the branch and open a PR into the right base.
- `scripts/flow.sh promote` → open the `beta → main` release PR.
- `scripts/flow.sh sync` → prune merged branches + dead worktrees.

**Agent autonomy — who may push / open PRs:**
- **No-live/no-beta repos** (local-only tools, placeholders — no live deployment AND no `beta`
  branch): an agent MAY run `scripts/flow.sh done` itself (push + open the PR). It must still
  NOT merge the PR and NOT `promote`.
- **Repos with a live deployment and/or a `beta` branch:** the agent commits and STOPS; the
  human runs `flow.sh done`, reviews, and merges/promotes.
- Always, regardless of tier: never push directly to `main`/`beta`, never merge or promote a
  PR, never `--no-verify`.

`main` and `beta` are protected by GitHub rulesets: no direct pushes, PR + green CI required.
Merges are squash-only; the head branch auto-deletes on merge.

## Security (non-negotiable — see SECURITY.md)

- NEVER commit secrets: no `.env`, API keys, tokens, `*.session.json`, cookies, private keys.
  Load secrets from env / keychain. A pre-commit hook blocks this; do not `--no-verify` around it.
- No secrets in frontend JS bundles; no source maps in production.
- Enforce authorization on every protected action (not just authentication). No IDOR — never trust
  user-supplied IDs/roles; scope every query to the authenticated user/tenant.
- Validate & sanitize all input at the boundary; parameterized queries only (no SQL/NoSQL injection);
  escape output (no XSS); CSRF protection on state-changing requests.
- Rate-limit login/signup/API/AI endpoints. Lock down CORS. Set security headers. Cookies =
  HttpOnly+Secure+SameSite. Verify webhook signatures. Enforce payment/subscription checks server-side.
- Treat AI input as untrusted (prompt injection); AI tools get the same authz as the user.
- No verbose error/stack traces or PII/tokens in logs or responses. Review generated code before merge.
