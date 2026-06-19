"""Unit tests for PhoneHub device-discovery output parsing.

These cover the real logic: parsing ``idevice_id -l`` / ``ideviceinfo`` and
``adb devices -l`` output. Subprocess is fully mocked — no network, no real
devices, no installed tools required.
"""

from __future__ import annotations

from unittest import mock

import pytest

from src.devices import Device, is_valid_identifier
from src import discovery


# --------------------------------------------------------------------------- #
# Identifier validation
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "identifier,expected",
    [
        ("00008110-001A2B3C4D5E6F00", True),
        ("emulator-5554", True),
        ("192.168.0.10:5555", True),
        ("ZY223abc_01", True),
        ("", False),
        ("a b", False),               # whitespace
        ("rm;rm", False),             # shell metacharacter
        ("$(whoami)", False),         # command substitution
        ("a/../b", False),            # path traversal chars
        ("x" * 200, False),           # overlong
    ],
)
def test_is_valid_identifier(identifier, expected):
    assert is_valid_identifier(identifier) is expected


# --------------------------------------------------------------------------- #
# idevice_id parsing
# --------------------------------------------------------------------------- #


def test_parse_idevice_id_multiple():
    out = "00008110-001A2B3C4D5E6F00\n00008030-0011AABBCCDDEE00\n"
    assert discovery.parse_idevice_id(out) == [
        "00008110-001A2B3C4D5E6F00",
        "00008030-0011AABBCCDDEE00",
    ]


def test_parse_idevice_id_with_transport_suffix():
    # Some versions append "(USB)" / "(Network)".
    out = "00008110-001A2B3C4D5E6F00 (USB)\n"
    assert discovery.parse_idevice_id(out) == ["00008110-001A2B3C4D5E6F00"]


def test_parse_idevice_id_empty():
    assert discovery.parse_idevice_id("") == []
    assert discovery.parse_idevice_id("\n  \n") == []


def test_parse_idevice_id_drops_invalid():
    # First token of each line is taken; tokens with metacharacters are dropped.
    out = "good-udid_01\n$(evil)\nbad;rm\n"
    assert discovery.parse_idevice_id(out) == ["good-udid_01"]


# --------------------------------------------------------------------------- #
# adb devices parsing
# --------------------------------------------------------------------------- #


def test_parse_adb_devices_multiple():
    out = (
        "List of devices attached\n"
        "emulator-5554   device product:sdk_gphone model:Pixel_7\n"
        "ZY223abc        device usb:1-1\n"
        "00fff           unauthorized\n"
        "10.0.0.5:5555   offline\n"
    )
    assert discovery.parse_adb_devices(out) == [
        ("emulator-5554", "device"),
        ("ZY223abc", "device"),
        ("00fff", "unauthorized"),
        ("10.0.0.5:5555", "offline"),
    ]


def test_parse_adb_devices_empty_list():
    # Header only — no attached devices.
    assert discovery.parse_adb_devices("List of devices attached\n\n") == []


def test_parse_adb_devices_skips_daemon_chatter():
    out = (
        "* daemon not running; starting now at tcp:5037 *\n"
        "* daemon started successfully *\n"
        "List of devices attached\n"
        "ZY223abc   device\n"
    )
    assert discovery.parse_adb_devices(out) == [("ZY223abc", "device")]


def test_parse_adb_devices_drops_invalid_serial():
    # A serial token containing shell metacharacters is rejected.
    out = "List of devices attached\n$(evil)   device\n"
    assert discovery.parse_adb_devices(out) == []


# --------------------------------------------------------------------------- #
# discover_ios — tool missing / present (subprocess mocked)
# --------------------------------------------------------------------------- #


def _completed(stdout="", returncode=0):
    cp = mock.Mock()
    cp.stdout = stdout
    cp.returncode = returncode
    return cp


def test_discover_ios_tool_missing():
    with mock.patch.object(discovery, "tool_available", return_value=False):
        assert discovery.discover_ios() == []


def test_discover_ios_filenotfound_degrades():
    with mock.patch.object(discovery, "tool_available", return_value=True), \
         mock.patch.object(discovery, "_run", side_effect=FileNotFoundError):
        assert discovery.discover_ios() == []


def test_discover_ios_parses_and_enriches():
    list_cp = _completed(stdout="00008110-001A2B3C4D5E6F00\n")
    # ideviceinfo is called once per key (ProductType, ProductVersion).
    info_values = {"ProductType": "iPhone15,2", "ProductVersion": "17.4"}

    def fake_run(args):
        if args[:2] == ["idevice_id", "-l"]:
            return list_cp
        # ["ideviceinfo", "-u", udid, "-k", KEY]
        key = args[-1]
        return _completed(stdout=info_values[key])

    with mock.patch.object(discovery, "tool_available", return_value=True), \
         mock.patch.object(discovery, "_run", side_effect=fake_run):
        devices = discovery.discover_ios()

    assert devices == [
        Device(
            platform="ios",
            udid="00008110-001A2B3C4D5E6F00",
            model="iPhone15,2",
            os_version="17.4",
            status="connected",
        )
    ]


def test_discover_ios_info_failure_marks_unknown():
    list_cp = _completed(stdout="00008110-001A2B3C4D5E6F00\n")

    def fake_run(args):
        if args[:2] == ["idevice_id", "-l"]:
            return list_cp
        return _completed(returncode=1)  # ideviceinfo fails

    with mock.patch.object(discovery, "tool_available", return_value=True), \
         mock.patch.object(discovery, "_run", side_effect=fake_run):
        devices = discovery.discover_ios()

    assert len(devices) == 1
    assert devices[0].model == "unknown"
    assert devices[0].os_version == "unknown"
    assert devices[0].status == "connected"


# --------------------------------------------------------------------------- #
# discover_android — tool missing / present (subprocess mocked)
# --------------------------------------------------------------------------- #


def test_discover_android_tool_missing():
    with mock.patch.object(discovery, "tool_available", return_value=False):
        assert discovery.discover_android() == []


def test_discover_android_parses_and_enriches():
    list_out = "List of devices attached\nZY223abc   device\n"
    props = {"ro.product.model": "Pixel 7", "ro.build.version.release": "14"}

    def fake_run(args):
        if args[:2] == ["adb", "devices"]:
            return _completed(stdout=list_out)
        # ["adb", "-s", serial, "shell", "getprop", PROP]
        prop = args[-1]
        return _completed(stdout=props[prop])

    with mock.patch.object(discovery, "tool_available", return_value=True), \
         mock.patch.object(discovery, "_run", side_effect=fake_run):
        devices = discovery.discover_android()

    assert devices == [
        Device(
            platform="android",
            udid="ZY223abc",
            model="Pixel 7",
            os_version="14",
            status="connected",
        )
    ]


def test_discover_android_unauthorized_skips_getprop():
    list_out = "List of devices attached\n00fff   unauthorized\n"

    def fake_run(args):
        if args[:2] == ["adb", "devices"]:
            return _completed(stdout=list_out)
        raise AssertionError("getprop must not be called for non-'device' state")

    with mock.patch.object(discovery, "tool_available", return_value=True), \
         mock.patch.object(discovery, "_run", side_effect=fake_run):
        devices = discovery.discover_android()

    assert len(devices) == 1
    assert devices[0].status == "unauthorized"
    assert devices[0].model == "unknown"


def test_discover_android_empty_list():
    def fake_run(args):
        return _completed(stdout="List of devices attached\n\n")

    with mock.patch.object(discovery, "tool_available", return_value=True), \
         mock.patch.object(discovery, "_run", side_effect=fake_run):
        assert discovery.discover_android() == []


# --------------------------------------------------------------------------- #
# discover() — combined, both tools missing → empty, no crash
# --------------------------------------------------------------------------- #


def test_discover_both_missing_returns_empty():
    with mock.patch.object(discovery, "tool_available", return_value=False):
        assert discovery.discover() == []
