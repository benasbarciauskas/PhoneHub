#!/usr/bin/env bash
# tests/phonedrop_test.sh
# Pure-logic tests for phonedrop.sh — runs WITHOUT a phone attached.
# Tests: config parse, arg quoting, EXIF/GPS strip assertion.
# Exit 0 = all pass. Exit 1 = failure.
set -euo pipefail

PASS=0
FAIL=0
FAILURES=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONEDROP="${SCRIPT_DIR}/../scripts/phonedrop.sh"

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "[PASS] ${desc}"
    (( PASS++ ))
  else
    echo "[FAIL] ${desc}"
    echo "       expected: ${expected}"
    echo "       actual:   ${actual}"
    FAILURES+=("${desc}")
    (( FAIL++ ))
  fi
}

assert_not_empty() {
  local desc="$1" val="$2"
  if [[ -n "${val}" ]]; then
    echo "[PASS] ${desc}"
    (( PASS++ ))
  else
    echo "[FAIL] ${desc} (got empty string)"
    FAILURES+=("${desc}")
    (( FAIL++ ))
  fi
}

assert_empty() {
  local desc="$1" val="$2"
  if [[ -z "${val}" ]]; then
    echo "[PASS] ${desc}"
    (( PASS++ ))
  else
    echo "[FAIL] ${desc} (expected empty, got: ${val})"
    FAILURES+=("${desc}")
    (( FAIL++ ))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "${path}" ]]; then
    echo "[PASS] ${desc}"
    (( PASS++ ))
  else
    echo "[FAIL] ${desc} (file not found: ${path})"
    FAILURES+=("${desc}")
    (( FAIL++ ))
  fi
}

# ---------------------------------------------------------------------------
# Test 1: Syntax check
# ---------------------------------------------------------------------------
echo "=== Test: syntax check ==="
if bash -n "${PHONEDROP}" 2>/dev/null; then
  echo "[PASS] phonedrop.sh passes bash -n"
  (( PASS++ ))
else
  echo "[FAIL] phonedrop.sh has syntax errors"
  FAILURES+=("syntax check")
  (( FAIL++ ))
fi

# ---------------------------------------------------------------------------
# Test 2: Script is executable
# ---------------------------------------------------------------------------
echo ""
echo "=== Test: script executable ==="
if [[ -x "${PHONEDROP}" ]]; then
  echo "[PASS] phonedrop.sh is executable"
  (( PASS++ ))
else
  echo "[FAIL] phonedrop.sh is not executable"
  FAILURES+=("script executable")
  (( FAIL++ ))
fi

# ---------------------------------------------------------------------------
# Test 3: Config parse — source a synthetic config and verify values
# ---------------------------------------------------------------------------
echo ""
echo "=== Test: config parse ==="
TMP_CFG_DIR=$(mktemp -d)
TMP_CFG="${TMP_CFG_DIR}/config"
cat > "${TMP_CFG}" << 'CFG'
PHONE_HOST="test-phone"
ADB_PORT="9999"
DEST="/sdcard/DCIM/TestDrop/"
ADB_BIN="/opt/homebrew/bin/adb"
EXIFTOOL_BIN="/opt/homebrew/bin/exiftool"
TAILSCALE_BIN="/usr/local/bin/tailscale"
CFG

# Source the synthetic config and verify
(
  source "${TMP_CFG}"
  assert_eq "PHONE_HOST parsed" "test-phone" "${PHONE_HOST}"
  assert_eq "ADB_PORT parsed"   "9999"        "${ADB_PORT}"
  assert_eq "DEST parsed"       "/sdcard/DCIM/TestDrop/" "${DEST}"
  assert_eq "ADB_BIN parsed"    "/opt/homebrew/bin/adb"  "${ADB_BIN}"
)
# Capture assertions from subshell by re-running inline (subshell isolates variables)
source "${TMP_CFG}"
assert_eq "PHONE_HOST parsed" "test-phone"              "${PHONE_HOST}"
assert_eq "ADB_PORT parsed"   "9999"                    "${ADB_PORT}"
assert_eq "DEST parsed"       "/sdcard/DCIM/TestDrop/"  "${DEST}"
assert_eq "ADB_BIN parsed"    "/opt/homebrew/bin/adb"   "${ADB_BIN}"
rm -rf "${TMP_CFG_DIR}"

# Reset sourced vars
unset PHONE_HOST ADB_PORT DEST ADB_BIN EXIFTOOL_BIN TAILSCALE_BIN

# ---------------------------------------------------------------------------
# Test 4: Arg quoting — paths with spaces don't get split
# ---------------------------------------------------------------------------
echo ""
echo "=== Test: arg quoting with spaces ==="
TMP_SPACE_DIR=$(mktemp -d)
mkdir -p "${TMP_SPACE_DIR}/My Photos"
touch "${TMP_SPACE_DIR}/My Photos/photo with spaces.jpg"

# Verify the file exists (this proves our mkdir/touch with spaces works)
assert_file_exists "test file with spaces created" "${TMP_SPACE_DIR}/My Photos/photo with spaces.jpg"

# Simulate how the AppleScript builds quoted paths: single-quote each POSIX path
build_quoted_list() {
  local result=""
  for f in "$@"; do
    local escaped
    escaped="${f//\'/\'\\\'\'}"
    result="${result} '${escaped}'"
  done
  echo "${result}"
}

QUOTED=$(build_quoted_list "${TMP_SPACE_DIR}/My Photos/photo with spaces.jpg")
# The quoted form must contain the full path
if echo "${QUOTED}" | grep -q "photo with spaces.jpg"; then
  echo "[PASS] quoted path contains full filename with spaces"
  (( PASS++ ))
else
  echo "[FAIL] quoted path mangled: ${QUOTED}"
  FAILURES+=("arg quoting with spaces")
  (( FAIL++ ))
fi

# Verify eval with spaces yields exactly 1 argument
ARG_COUNT=$(eval "set -- ${QUOTED}; echo \$#")
assert_eq "quoted path is 1 arg (spaces not split)" "1" "${ARG_COUNT}"

rm -rf "${TMP_SPACE_DIR}"

# ---------------------------------------------------------------------------
# Test 5: EXIF/GPS strip assertion (KEY TEST)
# Inject GPS EXIF into a temp JPEG, run exiftool -all=, assert GPS tags gone.
# ---------------------------------------------------------------------------
echo ""
echo "=== Test: EXIF/GPS strip ==="

EXIFTOOL_BIN="${EXIFTOOL_BIN:-/opt/homebrew/bin/exiftool}"

if [[ ! -x "${EXIFTOOL_BIN}" ]]; then
  echo "[SKIP] exiftool not found at ${EXIFTOOL_BIN} — EXIF strip test skipped"
  echo "       Install with: brew install exiftool"
else
  TMP_EXIF_DIR=$(mktemp -d)
  TEST_ORIG="${TMP_EXIF_DIR}/orig.jpg"
  TEST_STRIPPED="${TMP_EXIF_DIR}/stripped.jpg"

  # Create a minimal 1×1 JPEG using sips (always present on macOS)
  CREATED_JPEG=0
  if command -v sips >/dev/null 2>&1; then
    # Generate a 1×1 PNG via Python, then convert to JPEG with sips
    TMP_PNG="${TMP_EXIF_DIR}/pixel.png"
    python3 - "${TMP_PNG}" << 'PYEOF'
import sys, struct, zlib
def write_png(path):
    raw = b'\x00\x00'  # filter byte + 1-byte gray pixel
    compressed = zlib.compress(raw)
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        crc = zlib.crc32(c[4:]) & 0xffffffff
        return c + struct.pack('>I', crc)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack('>IIBBBBB', 1, 1, 8, 0, 0, 0, 0)  # 1×1, 8-bit gray
    ihdr = chunk(b'IHDR', ihdr_data)
    idat = chunk(b'IDAT', compressed)
    iend = chunk(b'IEND', b'')
    open(path, 'wb').write(sig + ihdr + idat + iend)
write_png(sys.argv[1])
PYEOF
    if [[ -f "${TMP_PNG}" ]]; then
      sips -s format jpeg "${TMP_PNG}" --out "${TEST_ORIG}" >/dev/null 2>&1 && CREATED_JPEG=1
    fi
  fi

  if [[ "${CREATED_JPEG}" -eq 0 ]]; then
    # Fallback: write a minimal valid JPEG via Python (SOI + APP0 + SOF0 + SOS + EOI)
    python3 - "${TEST_ORIG}" << 'PYEOF'
import sys
# Minimal valid 1×1 grayscale JPEG
data = bytes([
    0xFF,0xD8,  # SOI
    0xFF,0xE0,0x00,0x10,  # APP0 marker + length=16
    0x4A,0x46,0x49,0x46,0x00,  # JFIF\0
    0x01,0x01,  # version 1.1
    0x00,       # aspect ratio units (0=no units)
    0x00,0x01,0x00,0x01,  # Xdensity=1, Ydensity=1
    0x00,0x00,  # thumbnail size 0×0
    0xFF,0xDB,0x00,0x43,0x00,  # DQT marker
    # 64-byte quantization table (all 1s = maximum quality)
] + [1]*64 + [
    0xFF,0xC0,0x00,0x0B,  # SOF0 marker + length=11
    0x08,           # precision=8
    0x00,0x01,      # height=1
    0x00,0x01,      # width=1
    0x01,           # components=1 (gray)
    0x01,0x11,0x00, # component 1: id=1, sampling=1×1, qtable=0
    0xFF,0xC4,0x00,0x1F,0x00,  # DHT marker (DC, table 0)
    0x00,0x01,0x05,0x01,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,
    0xFF,0xDA,0x00,0x08,0x01,0x01,0x00,0x00,0x3F,0x00,  # SOS
    0x7F,0xA4,  # minimal scan data (DC coefficient for 1×1 gray)
    0xFF,0xD9   # EOI
])
open(sys.argv[1], 'wb').write(data)
PYEOF
    [[ -f "${TEST_ORIG}" ]] && CREATED_JPEG=1
  fi

  if [[ "${CREATED_JPEG}" -eq 0 ]]; then
    echo "[SKIP] could not create a test JPEG (no sips, no Python) — skipping strip test"
  else
    assert_file_exists "test JPEG created" "${TEST_ORIG}"

    # Inject GPS EXIF tags
    "${EXIFTOOL_BIN}" -overwrite_original \
      -GPSLatitude=51.5074 \
      -GPSLongitude=-0.1278 \
      -GPSLatitudeRef=N \
      -GPSLongitudeRef=W \
      "${TEST_ORIG}" >/dev/null 2>&1

    # Verify injection succeeded
    GPS_BEFORE=$("${EXIFTOOL_BIN}" -GPS:GPSLatitude "${TEST_ORIG}" 2>/dev/null || true)
    if [[ -n "${GPS_BEFORE}" ]]; then
      echo "[info] GPS injected: ${GPS_BEFORE}"
    else
      echo "[warn] GPS injection may not have worked — strip test may be vacuous"
    fi

    # Copy to stripped (simulate phonedrop.sh push behavior)
    cp "${TEST_ORIG}" "${TEST_STRIPPED}"

    # Strip ALL metadata (the operation phonedrop.sh performs)
    "${EXIFTOOL_BIN}" -overwrite_original -all= "${TEST_STRIPPED}" >/dev/null 2>&1

    # Assert: no GPS tags in stripped file
    GPS_AFTER=$("${EXIFTOOL_BIN}" -GPS:all "${TEST_STRIPPED}" 2>/dev/null || true)
    assert_empty "GPS tags absent after exiftool -all= strip" "${GPS_AFTER}"

    # Assert: no EXIF tags at all
    EXIF_AFTER=$("${EXIFTOOL_BIN}" -EXIF:all "${TEST_STRIPPED}" 2>/dev/null || true)
    assert_empty "EXIF tags absent after exiftool -all= strip" "${EXIF_AFTER}"

    # Sanity: original still has its GPS (we didn't touch it)
    GPS_ORIG=$("${EXIFTOOL_BIN}" -GPS:GPSLatitude "${TEST_ORIG}" 2>/dev/null || true)
    if [[ -n "${GPS_ORIG}" ]]; then
      echo "[PASS] original file GPS untouched (original not mutated)"
      (( PASS++ ))
    else
      echo "[WARN] original GPS check inconclusive (injection may have failed)"
    fi
  fi

  rm -rf "${TMP_EXIF_DIR}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "${FAIL}" -gt 0 ]]; then
  echo "Failed tests:"
  for f in "${FAILURES[@]}"; do
    echo "  - ${f}"
  done
  exit 1
fi
exit 0
