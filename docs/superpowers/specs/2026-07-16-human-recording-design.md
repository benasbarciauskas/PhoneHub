# Human Recording Design

## Goal

Let a user record their own interaction with the focused device mirror as ordinary,
editable Builder timeline steps. Raw desktop events are never persisted or logged.

## Architecture

`PhoneHubCore` owns a deterministic `HumanRecordingTranslator`. It accepts already
scoped, synthesized event descriptions and emits `AutomationStep` values. It handles
click, double-click, long-press, swipe, scroll bursts, text buffering, Return/Delete,
and bounded waits. Separate pure helpers map window-content points into iOS points or
Android framebuffer pixels and parse `adb shell wm size` output.

The app target owns `HumanRecorder`, a `@MainActor` lifecycle object. It installs one
listen-only session event tap, resolves the focused mirror window through AX, and
rejects events synchronously unless they belong to that exact window. Mouse and
scroll events require both the mirror app to be frontmost and the cursor AX hit-test
to resolve to the target window. Key events require the mirror app and target window
to be focused. No rejected event crosses the scoping boundary.

## Geometry

At start, and lazily once per short event batch, the recorder reads the target AX
position and size. iPhone Mirroring's MCP `status` supplies the authoritative content
point size. The title-bar height is `max(0, AX height - content height)`; points above
that strip are rejected and accepted Y coordinates subtract the strip. This is the
simplest robust interpretation of AX's whole-window frame versus mirroir's content
size. scrcpy is launched borderless, so its entire AX frame is content; points scale
independently by framebuffer pixels divided by AX window points.

## Translation decisions

- A left down/up under 300 ms and under 6 points becomes a tap after the double-click
  window expires. A matching second click within 350 ms and 10 points replaces it
  with a double tap.
- A stationary press of at least 600 ms becomes a long press. Movement of at least
  40 points becomes a dominant-axis swipe. Ambiguous 300-599 ms presses and movement
  between 6 and 40 points are discarded rather than guessed.
- Scroll deltas accumulate for 400 ms and become the opposite phone-finger gesture.
- Printable keys form one text step. Mouse/non-printable input or two seconds idle
  flushes it. Return and Delete use explicit key steps; unknown non-printable keys and
  right-click only flush pending input because no required phone action maps to them.
- Step gaps of at least 800 ms are rounded to 100 ms, capped at 5000 ms, and inserted
  as waits.

## Builder and privacy UI

The Builder toolbar starts/stops recording for the focused device. While active it
shows a red indicator, instruction banner, Stop control, and a mouse-only notice when
Input Monitoring is unavailable. The first available Record control also shows the
plain-text password warning for the session. Closing/unmounting the Builder, mirror
deactivation/termination, or PhoneHub termination deterministically invalidates the
tap and removes its run-loop source.

After a recording stops, a summary row can call the existing `AutomationEngine`
condense path with a description-oriented goal. Its returned minimal steps are not
substituted into the timeline; they are summarized locally into editable natural
language shown above the timeline. This reuses provider selection and execution
without introducing another provider integration.

## Testing

Pure unit tests cover every translation threshold, flush rule, wait rule, both
coordinate systems, `wm size` parsing, and recorded tap/text/swipe execution mappings.
App tests cover permission-facing pure behavior where practical. Final gates are the
specified full Swift test command and Swift build command.
