"""Device discovery for PhoneHub.

Discovers the owner's connected iOS and Android devices by shelling out to
``libimobiledevice`` (iOS) and ``adb`` (Android) and parsing their output.

The pure parsing functions (``parse_idevice_id``, ``parse_adb_devices``) carry
the real logic and are unit-tested with mocked subprocess output. The
``discover_*`` functions wire those parsers to live subprocess calls and
degrade gracefully when a tool is missing or a device is unreachable.

Security: no ``shell=True`` anywhere; every argv is a list; every device
identifier is validated against a strict charset before it reaches a command.
"""

from __future__ import annotations

import subprocess
from typing import List

from .devices import Device, is_valid_identifier, tool_available

# Bound every subprocess call so a wedged tool/device can never hang the UI.
_TIMEOUT_SECONDS = 10


def _run(args: List[str]) -> "subprocess.CompletedProcess[str]":
    """Run a command (argv list, never a shell string) and capture text output.

    Raises the usual subprocess exceptions (FileNotFoundError,
    TimeoutExpired, ...) which callers handle to degrade gracefully.
    """
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=_TIMEOUT_SECONDS,
        check=False,
    )


# --------------------------------------------------------------------------- #
# Pure parsers (the real logic — unit-tested)
# --------------------------------------------------------------------------- #


def parse_idevice_id(output: str) -> List[str]:
    """Parse ``idevice_id -l`` output into a list of UDIDs.

    ``idevice_id -l`` prints one UDID per line. Some versions append a
    transport suffix (e.g. ``00008110-... (USB)``); we take the first token of
    each line. Blank lines and invalid identifiers are dropped.
    """
    udids: List[str] = []
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        token = line.split()[0]
        if is_valid_identifier(token):
            udids.append(token)
    return udids


def parse_adb_devices(output: str) -> List[tuple[str, str]]:
    """Parse ``adb devices -l`` output into ``(serial, state)`` pairs.

    Example input::

        List of devices attached
        emulator-5554   device product:sdk_gphone model:Pixel_7 ...
        ZY223abc        device ...
        00fff           unauthorized

    The header line and any blank lines are skipped. Lines starting with
    ``*`` (daemon startup chatter) are skipped. Each remaining line is split on
    whitespace: token 0 is the serial, token 1 is the state. Serials failing
    validation are dropped.
    """
    pairs: List[tuple[str, str]] = []
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("List of devices"):
            continue
        if line.startswith("*"):  # e.g. "* daemon started successfully *"
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        serial, state = parts[0], parts[1]
        if is_valid_identifier(serial):
            pairs.append((serial, state))
    return pairs


# --------------------------------------------------------------------------- #
# iOS discovery
# --------------------------------------------------------------------------- #


def _ideviceinfo_value(udid: str, key: str) -> str:
    """Return a single ProductType/ProductVersion-style value, or "" on failure."""
    if not is_valid_identifier(udid):
        return ""
    try:
        result = _run(["ideviceinfo", "-u", udid, "-k", key])
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def discover_ios() -> List[Device]:
    """Discover connected iOS devices via libimobiledevice.

    Degrades gracefully: if ``idevice_id`` is missing or errors, returns []
    rather than raising. Per-device info lookups that fail leave that field as
    "unknown" instead of dropping the device.
    """
    if not tool_available("idevice_id"):
        return []
    try:
        listing = _run(["idevice_id", "-l"])
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return []
    if listing.returncode != 0:
        return []

    devices: List[Device] = []
    for udid in parse_idevice_id(listing.stdout):
        model = _ideviceinfo_value(udid, "ProductType") or "unknown"
        version = _ideviceinfo_value(udid, "ProductVersion") or "unknown"
        devices.append(
            Device(
                platform="ios",
                udid=udid,
                model=model,
                os_version=version,
                status="connected",
            )
        )
    return devices


# --------------------------------------------------------------------------- #
# Android discovery
# --------------------------------------------------------------------------- #


def _adb_getprop(serial: str, prop: str) -> str:
    """Return a single getprop value for a device, or "" on failure."""
    if not is_valid_identifier(serial):
        return ""
    try:
        result = _run(["adb", "-s", serial, "shell", "getprop", prop])
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def discover_android() -> List[Device]:
    """Discover connected Android devices via adb.

    Degrades gracefully: missing ``adb`` → []. Devices that are present but not
    in the ``device`` state (e.g. ``unauthorized``, ``offline``) are still
    listed with that status, but we skip the getprop calls (they would fail).
    """
    if not tool_available("adb"):
        return []
    try:
        listing = _run(["adb", "devices", "-l"])
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return []
    if listing.returncode != 0:
        return []

    devices: List[Device] = []
    for serial, state in parse_adb_devices(listing.stdout):
        if state == "device":
            model = _adb_getprop(serial, "ro.product.model") or "unknown"
            version = _adb_getprop(serial, "ro.build.version.release") or "unknown"
            status = "connected"
        else:
            # unauthorized / offline / no permissions: don't probe further.
            model = "unknown"
            version = "unknown"
            status = state
        devices.append(
            Device(
                platform="android",
                udid=serial,
                model=model,
                os_version=version,
                status=status,
            )
        )
    return devices


def discover() -> List[Device]:
    """Discover all connected devices across both platforms.

    Never raises for missing tools or unreachable devices — worst case it
    returns a shorter (or empty) list.
    """
    return discover_ios() + discover_android()
