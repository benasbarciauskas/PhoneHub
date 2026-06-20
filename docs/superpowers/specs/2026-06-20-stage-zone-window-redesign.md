# Stage-Zone Window Redesign (Wall z-order fix)

_Date: 2026-06-20 · Status: QUEUED (not yet implemented) · Priority: medium_

## Problem

PhoneHub orchestrates **native** mirror windows (iPhone Mirroring, scrcpy) by AX-positioning
them into a "stage" area that is drawn **inside PhoneHub's own window**. Because PhoneHub is
the active app, its window sits **above** the mirror windows, so in **Wall mode** the docked
mirrors render *behind* PhoneHub's stage (you see the tile label, not the screen). Focus mode
happens to work, Wall does not.

`dockWindow` already calls `kAXRaiseAction` on the mirror — confirmed insufficient: raising a
window inside a **non-frontmost** app does not lift it above the active app's (PhoneHub's)
window. The only ways to force it are bad:
- **Activate the mirror app** → steals focus (and was part of the runaway-loop hazard). Rejected.
- **Lower PhoneHub's `NSWindow.level`** so mirrors float above its stage → then *every* other
  app's window (Chrome, etc.) also floats above PhoneHub, and PhoneHub can't come forward. Rejected.

## Approach: sidebar-only window + open stage zone

Stop drawing a stage *inside* PhoneHub's window. Instead:

1. **PhoneHub's main window becomes sidebar-only** — a narrow window (~260pt: the device list +
   Focus/Wall toggle + refresh + future controls). No stage backdrop in PhoneHub's own window.
2. **The "stage zone" is a screen region beside the sidebar** (the screen's `visibleFrame` minus
   the sidebar's footprint). PhoneHub computes that rect and AX-docks the mirror window(s) into it
   — they float as ordinary windows on the desktop, **not behind any PhoneHub surface**, so there
   is no cross-app z-order conflict at all.
3. **Focus mode** → one mirror centered/fit in the stage zone. **Wall mode** → `gridTileRects`
   over the stage zone, one mirror per tile (Android scrcpy resizes to tile; the single live
   iPhone-Mirroring window centers in its tile).
4. Recompute the stage zone on screen change / sidebar move; reuse the existing dedup'd
   `report()` + reposition-only resync + `menuFittedIOSDeviceIDs` one-shot-fit guards (do NOT
   reintroduce menu-fit on resync — see the runaway-loop fix / playbook AX-runaway lesson).

## Open design questions (resolve at execution time)

- **Dark backdrop behind the stage zone?** Losing PhoneHub's OLED stage means the desktop/other
  windows show in the gaps around a mirror. Option: a separate **borderless, non-activating,
  low-level backdrop window** (near-black) covering the stage zone, ordered *below* the mirrors
  but above the desktop. This restores the OLED look **without** the original z-order trap
  (the backdrop is deliberately below the mirrors and never the active window). Risk: another
  window to keep positioned + ordered. Decide: ship without backdrop first (simplest), add the
  backdrop window as a second step if the bare-desktop look is unacceptable.
- **Sidebar placement** — pin to left of the main display? Remember last position? Let the user
  move it (and re-dock the zone relative to it)?
- **Multi-display** — which display hosts the stage zone (the one the sidebar is on? largest?).

## Non-goals / constraints

- Manual control only — no automation/evasion/farm (project scope guard stands).
- No focus-stealing, no menu actions on resync, no per-layout AX driving (lockup-class bugs).
- Keep the menu-driven fit (View → Larger/Smaller) and nav rail; they operate on the docked
  mirror regardless of where the stage lives.

## Verification plan (when built)

- Build + `swift test`.
- Live: Focus mode → mirror floats in the stage zone, fully visible (not behind anything),
  sidebar always clickable. Wall mode → multiple mirrors tile in the zone, all visible at once.
- Verify **without hijacking the user's foreground** — the whole point is the mirrors are normal
  desktop windows; confirm via window-bounds math + a single user-driven screenshot, not by
  force-activating apps.

## Why queued, not built now

Cross-app window management is fiddly and already caused one Mac-locking regression this build;
verifying it kept requiring disruptive foreground takeover of the user's live screen. This is a
deliberate medium-size piece to execute later via the normal build loop (plan → Codex → review →
verify), not a quick patch. Focus mode works today, so Wall z-order is not blocking.
