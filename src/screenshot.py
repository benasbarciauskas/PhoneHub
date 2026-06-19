"""Capture a screenshot from a connected device.

- Android: ``adb -s <serial> exec-out screencap -p`` streams raw PNG bytes to
  stdout, which we write under ``screenshots/``.
- iOS: ``idevicescreenshot -u <udid> <path>``. This needs a mounted developer
  disk image; on failure we degrade gracefully (return ``None`` + a clear
  message) instead of raising.

Security: no ``shell=True``; argv is always a list; identifiers are validated;
output filenames are derived from validated identifiers + a timestamp (never
from raw external strings), so there is no path traversal.
"""

from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .devices import Device, require_valid_identifier, tool_available

# Screenshots live in a gitignored directory at the repo root.
_SCREENSHOT_DIR = Path(__file__).resolve().parent.parent / "screenshots"

_TIMEOUT_SECONDS = 30


@dataclass
class CaptureResult:
    """Outcome of a screenshot request."""

    path: Optional[Path]
    message: str

    @property
    def ok(self) -> bool:
        return self.path is not None


def _output_path(device: Device) -> Path:
    """Build a safe, unique output path from the (validated) identifier."""
    safe_id = require_valid_identifier(device.udid)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    _SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
    return _SCREENSHOT_DIR / f"{device.platform}_{safe_id}_{stamp}.png"


def _capture_android(device: Device) -> CaptureResult:
    if not tool_available("adb"):
        return CaptureResult(None, "adb not found on PATH.")
    try:
        serial = require_valid_identifier(device.udid)
        out_path = _output_path(device)
    except ValueError as exc:
        return CaptureResult(None, str(exc))
    try:
        result = subprocess.run(
            ["adb", "-s", serial, "exec-out", "screencap", "-p"],
            capture_output=True,
            timeout=_TIMEOUT_SECONDS,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        return CaptureResult(None, f"adb screencap failed: {exc}")
    if result.returncode != 0 or not result.stdout:
        detail = result.stderr.decode("utf-8", "replace").strip() or "no image data"
        return CaptureResult(None, f"adb screencap failed: {detail}")
    out_path.write_bytes(result.stdout)
    return CaptureResult(out_path, f"Saved screenshot to {out_path.name}.")


def _capture_ios(device: Device) -> CaptureResult:
    if not tool_available("idevicescreenshot"):
        return CaptureResult(None, "idevicescreenshot not found on PATH.")
    try:
        udid = require_valid_identifier(device.udid)
        out_path = _output_path(device)
    except ValueError as exc:
        return CaptureResult(None, str(exc))
    try:
        result = subprocess.run(
            ["idevicescreenshot", "-u", udid, str(out_path)],
            capture_output=True,
            text=True,
            timeout=_TIMEOUT_SECONDS,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        return CaptureResult(None, f"idevicescreenshot failed: {exc}")
    if result.returncode != 0 or not out_path.exists():
        detail = result.stderr.strip() or "unknown error"
        # Most common cause: developer disk image not mounted.
        return CaptureResult(
            None,
            f"idevicescreenshot failed ({detail}). "
            "iOS screenshots need a mounted developer disk image.",
        )
    return CaptureResult(out_path, f"Saved screenshot to {out_path.name}.")


def capture(device: Device) -> CaptureResult:
    """Capture a screenshot. Returns a ``CaptureResult`` (never raises).

    On success ``result.path`` is the PNG path; on failure it is ``None`` and
    ``result.message`` explains why.
    """
    if device.platform == "android":
        return _capture_android(device)
    if device.platform == "ios":
        return _capture_ios(device)
    return CaptureResult(None, f"Unknown platform: {device.platform!r}")
