"""Shared device model and validation helpers for PhoneHub.

These primitives are deliberately tiny and dependency-free so every module
(discovery, focus, screenshot, dashboard) and the tests can share one strict
definition of "a device" and one strict definition of "a safe identifier".
"""

from __future__ import annotations

import re
import shutil
from dataclasses import dataclass

# Strict charset for device identifiers (iOS UDIDs, Android serials).
# Real-world identifiers are hex UDIDs, "host:port" network serials, emulator
# names ("emulator-5554"), etc. We allow only these characters and reject
# anything that could be used to break out of an argv element. Even though we
# never use shell=True, validating here is defence-in-depth at the boundary.
_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9.:_-]+$")

# Upper bound to reject absurd / hostile input early.
_MAX_IDENTIFIER_LEN = 128


@dataclass(frozen=True)
class Device:
    """A single connected device.

    Attributes:
        platform: "ios" or "android".
        udid: The iOS UDID or the Android serial (the identifier passed to
            ``-u`` / ``-s`` on the respective CLI tools).
        model: Human-readable model name (e.g. "iPhone15,2", "Pixel 7").
        os_version: OS version string (e.g. "17.4", "14").
        status: Connection / availability status (e.g. "connected",
            "unauthorized", "offline", "unknown").
    """

    platform: str
    udid: str
    model: str
    os_version: str
    status: str

    @property
    def short_id(self) -> str:
        """A short, display-friendly form of the identifier."""
        if len(self.udid) <= 12:
            return self.udid
        return f"{self.udid[:6]}…{self.udid[-4:]}"


def is_valid_identifier(identifier: str) -> bool:
    """Return True if ``identifier`` is safe to pass as a CLI argument.

    A valid identifier is a non-empty string of bounded length containing only
    ``[A-Za-z0-9.:_-]``. This rejects whitespace, shell metacharacters, option
    injection (a leading ``-`` is allowed by charset but callers should still
    pass identifiers positionally after ``--``/``-u``/``-s``), and overlong
    input.
    """
    if not isinstance(identifier, str):
        return False
    if not identifier or len(identifier) > _MAX_IDENTIFIER_LEN:
        return False
    return bool(_IDENTIFIER_RE.match(identifier))


def require_valid_identifier(identifier: str) -> str:
    """Return ``identifier`` if valid, else raise ``ValueError``.

    Use this at any boundary right before building an argv list.
    """
    if not is_valid_identifier(identifier):
        raise ValueError(f"Invalid / unsafe device identifier: {identifier!r}")
    return identifier


def tool_available(name: str) -> bool:
    """Return True if a CLI tool is resolvable on PATH."""
    return shutil.which(name) is not None
