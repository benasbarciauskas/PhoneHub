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
