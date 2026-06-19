"""Bring a device's mirroring surface to the foreground.

- iOS: activate Apple's native **iPhone Mirroring** app via AppleScript
  (``osascript``). NOTE: Apple's iPhone Mirroring supports only ONE mirrored
  iPhone at a time, so this simply brings the existing iPhone Mirroring window
  forward; it does not (and cannot) select between multiple iPhones.
- Android: launch ``scrcpy -s <serial>`` non-blocking via ``Popen`` so the
  caller (and the UI thread) is never blocked while the mirror window runs.

Security: no ``shell=True``; argv is always a list; identifiers are validated.
"""

from __future__ import annotations

import subprocess
from dataclasses import dataclass

from .devices import Device, require_valid_identifier, tool_available


@dataclass
class FocusResult:
    """Outcome of a focus request."""

    ok: bool
    message: str


# AppleScript: activate the iPhone Mirroring app (bring its window forward).
_IPHONE_MIRRORING_APPLESCRIPT = 'tell application "iPhone Mirroring" to activate'


def _focus_ios(device: Device) -> FocusResult:
    if not tool_available("osascript"):
        return FocusResult(False, "osascript not found (macOS only).")
    try:
        result = subprocess.run(
            ["osascript", "-e", _IPHONE_MIRRORING_APPLESCRIPT],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        return FocusResult(False, f"Failed to launch iPhone Mirroring: {exc}")
    if result.returncode != 0:
        detail = result.stderr.strip() or "unknown error"
        return FocusResult(False, f"iPhone Mirroring activation failed: {detail}")
    return FocusResult(
        True,
        "Brought iPhone Mirroring forward (Apple allows one mirrored iPhone at a time).",
    )


def _focus_android(device: Device) -> FocusResult:
    if not tool_available("scrcpy"):
        return FocusResult(False, "scrcpy not found on PATH.")
    try:
        serial = require_valid_identifier(device.udid)
    except ValueError as exc:
        return FocusResult(False, str(exc))
    try:
        # Non-blocking: scrcpy owns its own window for the session's lifetime.
        subprocess.Popen(
            ["scrcpy", "-s", serial],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (FileNotFoundError, OSError) as exc:
        return FocusResult(False, f"Failed to launch scrcpy: {exc}")
    return FocusResult(True, f"Launched scrcpy for {device.short_id}.")


def focus(device: Device) -> FocusResult:
    """Focus / mirror the given device. Never raises.

    Returns a ``FocusResult`` describing what happened so the UI can surface a
    clear message instead of a stack trace.
    """
    if device.platform == "ios":
        return _focus_ios(device)
    if device.platform == "android":
        return _focus_android(device)
    return FocusResult(False, f"Unknown platform: {device.platform!r}")
