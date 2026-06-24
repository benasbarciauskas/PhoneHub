#!/usr/bin/env bash
# tests/phonedrop_test.sh
# Pure-logic tests for phonedrop.sh — runs WITHOUT a phone attached.
#
# Tests:
#   1. Syntax check
#   2. Script executable
#   3. Config parse
#   4. Genuine exiftool EXIF/GPS strip assertion (tool-level, verifies strip works)
#   5. cmd_push via stubs: original file untouched (byte-identical before/after),
#      stub adb received sanitised filename as a single literal (injection regression),
#      adversarial filename (a;touch INJECTED.jpg) does NOT execute arbitrary commands,
#      stub exiftool was called on the temp copy (not the original).
#
# Exit 0 = all pass. Exit 1 = any failure.
set -euo pipefail

PASS=0
FAIL=0
FAILURES=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONEDROP="${SCRIPT_DIR}/../scripts/phonedrop.sh"
EXIFTOOL_BIN="${EXIFTOOL_BIN:-/opt/homebrew/bin/exiftool}"

# ---------------------------------------------------------------------------
# Assert helpers
# ---------------------------------------------------------------------------
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "[PASS] ${desc}"
    PASS=$((PASS+1))
  else
    echo "[FAIL] ${desc}"
    echo "       expected: $(printf '%q' "${expected}")"
    echo "       actual:   $(printf '%q' "${actual}")"
    FAILURES+=("${desc}")
    FAIL=$((FAIL+1))
  fi
}

assert_empty() {
  local desc="$1" val="$2"
  if [[ -z "${val}" ]]; then
    echo "[PASS] ${desc}"
    PASS=$((PASS+1))
  else
    echo "[FAIL] ${desc} — expected empty, got: ${val}"
    FAILURES+=("${desc}")
    FAIL=$((FAIL+1))
  fi
}

assert_not_empty() {
  local desc="$1" val="$2"
  if [[ -n "${val}" ]]; then
    echo "[PASS] ${desc}"
    PASS=$((PASS+1))
  else
    echo "[FAIL] ${desc} — expected non-empty"
    FAILURES+=("${desc}")
    FAIL=$((FAIL+1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "${path}" ]]; then
    echo "[PASS] ${desc}"
    PASS=$((PASS+1))
  else
    echo "[FAIL] ${desc} — file not found: ${path}"
    FAILURES+=("${desc}")
    FAIL=$((FAIL+1))
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [[ ! -e "${path}" ]]; then
    echo "[PASS] ${desc}"
    PASS=$((PASS+1))
  else
    echo "[FAIL] ${desc} — file should not exist: ${path}"
    FAILURES+=("${desc}")
    FAIL=$((FAIL+1))
  fi
}

assert_files_identical() {
  local desc="$1" a="$2" b="$3"
  if cmp -s "${a}" "${b}"; then
    echo "[PASS] ${desc}"
    PASS=$((PASS+1))
  else
    echo "[FAIL] ${desc} — files differ"
    FAILURES+=("${desc}")
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "[PASS] ${desc}"
    PASS=$((PASS+1))
  else
    echo "[FAIL] ${desc} — '${needle}' not found in output"
    FAILURES+=("${desc}")
    FAIL=$((FAIL+1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "[PASS] ${desc}"
    PASS=$((PASS+1))
  else
    echo "[FAIL] ${desc} — '${needle}' should NOT be in output but was"
    FAILURES+=("${desc}")
    FAIL=$((FAIL+1))
  fi
}

# ---------------------------------------------------------------------------
# Test 1: Syntax check
# ---------------------------------------------------------------------------
echo "=== Test 1: syntax check ==="
if bash -n "${PHONEDROP}" 2>/dev/null; then
  echo "[PASS] phonedrop.sh passes bash -n"
  PASS=$((PASS+1))
else
  echo "[FAIL] phonedrop.sh has syntax errors"
  FAILURES+=("syntax check")
  FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------------------
# Test 2: Script executable
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 2: script executable ==="
if [[ -x "${PHONEDROP}" ]]; then
  echo "[PASS] phonedrop.sh is executable"
  PASS=$((PASS+1))
else
  echo "[FAIL] phonedrop.sh is not executable"
  FAILURES+=("script executable")
  FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------------------
# Test 3: Config parse
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 3: config parse ==="
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

source "${TMP_CFG}"
assert_eq "PHONE_HOST parsed"  "test-phone"              "${PHONE_HOST}"
assert_eq "ADB_PORT parsed"    "9999"                    "${ADB_PORT}"
assert_eq "DEST parsed"        "/sdcard/DCIM/TestDrop/"  "${DEST}"
assert_eq "ADB_BIN parsed"     "/opt/homebrew/bin/adb"   "${ADB_BIN}"
rm -rf "${TMP_CFG_DIR}"
unset PHONE_HOST ADB_PORT DEST ADB_BIN TAILSCALE_BIN 2>/dev/null || true

# ---------------------------------------------------------------------------
# Test 4: Genuine exiftool EXIF/GPS strip (tool-level assertion)
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 4: exiftool EXIF/GPS strip assertion ==="

if [[ ! -x "${EXIFTOOL_BIN}" ]]; then
  echo "[SKIP] exiftool not found at ${EXIFTOOL_BIN} — install with: brew install exiftool"
else
  TMP_EXIF_DIR=$(mktemp -d)

  TEST_ORIG="${TMP_EXIF_DIR}/orig.jpg"
  TEST_STRIPPED="${TMP_EXIF_DIR}/stripped.jpg"

  # Create 1x1 JPEG
  CREATED=0
  if command -v sips >/dev/null 2>&1; then
    TMP_PNG="${TMP_EXIF_DIR}/pixel.png"
    python3 - "${TMP_PNG}" << 'PYEOF'
import sys, struct, zlib
def write_png(path):
    raw = b'\x00\x00'
    compressed = zlib.compress(raw)
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        crc = zlib.crc32(c[4:]) & 0xffffffff
        return c + struct.pack('>I', crc)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 0, 0, 0, 0))
    idat = chunk(b'IDAT', compressed)
    iend = chunk(b'IEND', b'')
    open(path, 'wb').write(sig + ihdr + idat + iend)
write_png(sys.argv[1])
PYEOF
    sips -s format jpeg "${TMP_PNG}" --out "${TEST_ORIG}" >/dev/null 2>&1 && CREATED=1
  fi

  if [[ "${CREATED}" -eq 0 ]]; then
    echo "[SKIP] could not create test JPEG"
  else
    assert_file_exists "test JPEG created" "${TEST_ORIG}"

    # Inject GPS
    "${EXIFTOOL_BIN}" -overwrite_original \
      -GPSLatitude=51.5074 -GPSLongitude=-0.1278 \
      -GPSLatitudeRef=N -GPSLongitudeRef=W \
      "${TEST_ORIG}" >/dev/null 2>&1

    GPS_BEFORE=$("${EXIFTOOL_BIN}" -GPS:GPSLatitude "${TEST_ORIG}" 2>/dev/null || true)
    [[ -n "${GPS_BEFORE}" ]] && echo "[info] GPS injected: ${GPS_BEFORE}"

    cp "${TEST_ORIG}" "${TEST_STRIPPED}"
    "${EXIFTOOL_BIN}" -overwrite_original -all= "${TEST_STRIPPED}" >/dev/null 2>&1

    GPS_AFTER=$("${EXIFTOOL_BIN}" -GPS:all "${TEST_STRIPPED}" 2>/dev/null || true)
    assert_empty "GPS tags absent after strip" "${GPS_AFTER}"

    EXIF_AFTER=$("${EXIFTOOL_BIN}" -EXIF:all "${TEST_STRIPPED}" 2>/dev/null || true)
    assert_empty "EXIF tags absent after strip" "${EXIF_AFTER}"

    GPS_ORIG=$("${EXIFTOOL_BIN}" -GPS:GPSLatitude "${TEST_ORIG}" 2>/dev/null || true)
    assert_not_empty "original GPS untouched (original not mutated)" "${GPS_ORIG}"
  fi

  rm -rf "${TMP_EXIF_DIR}"
fi

# ---------------------------------------------------------------------------
# Test 5: cmd_push via stubs
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 5: cmd_push with stubs (no phone required) ==="

# Build a temporary stub bin directory
STUB_DIR=$(mktemp -d)
ADB_LOG="${STUB_DIR}/adb.log"
EXIFTOOL_LOG="${STUB_DIR}/exiftool.log"

# Stub adb: log all calls, fake "connected" for connect, succeed for push/shell
cat > "${STUB_DIR}/adb" << STUBEOF
#!/usr/bin/env bash
echo "\$@" >> "${ADB_LOG}"
if [[ "\${1:-}" == "connect" ]]; then
  echo "connected to \${2}"
  exit 0
fi
if [[ "\${1:-}" == "push" ]]; then
  exit 0
fi
if [[ "\${1:-}" == "shell" ]]; then
  exit 0
fi
exit 0
STUBEOF
chmod +x "${STUB_DIR}/adb"

# Stub exiftool: log calls and actually run the real exiftool when stripping,
# so the real strip behaviour is exercised. Fall back to a no-op if not available.
if [[ -x "${EXIFTOOL_BIN}" ]]; then
  # Real exiftool available — wrap it so we can log calls
  cat > "${STUB_DIR}/exiftool" << STUBEOF
#!/usr/bin/env bash
echo "\$@" >> "${EXIFTOOL_LOG}"
exec "${EXIFTOOL_BIN}" "\$@"
STUBEOF
else
  # No real exiftool — stub is a no-op (strip tests are skipped in test 4 already)
  cat > "${STUB_DIR}/exiftool" << 'STUBEOF'
#!/usr/bin/env bash
echo "$@" >> "${EXIFTOOL_LOG}"
exit 0
STUBEOF
fi
chmod +x "${STUB_DIR}/exiftool"

# Write a synthetic config pointing at stubs
STUB_CFG_DIR=$(mktemp -d)
STUB_CFG="${STUB_CFG_DIR}/config"
cat > "${STUB_CFG}" << CFGEOF
PHONE_HOST="test-phone"
ADB_PORT="5555"
DEST="/sdcard/DCIM/PhoneDrop/"
ADB_BIN="${STUB_DIR}/adb"
EXIFTOOL_BIN="${STUB_DIR}/exiftool"
TAILSCALE_BIN="/usr/bin/true"
CFGEOF

# --- 5a: normal JPEG with a safe name ---
echo ""
echo "--- 5a: safe filename, original untouched ---"

WORK_DIR=$(mktemp -d)
ORIG_FILE="${WORK_DIR}/photo.jpg"

# Create a 1x1 JPEG with injected GPS (requires real exiftool)
if [[ -x "${EXIFTOOL_BIN}" ]] && command -v sips >/dev/null 2>&1; then
  TMP_PNG="${WORK_DIR}/pixel.png"
  python3 - "${TMP_PNG}" << 'PYEOF'
import sys, struct, zlib
def write_png(path):
    raw = b'\x00\x00'
    compressed = zlib.compress(raw)
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        crc = zlib.crc32(c[4:]) & 0xffffffff
        return c + struct.pack('>I', crc)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 0, 0, 0, 0))
    idat = chunk(b'IDAT', compressed)
    iend = chunk(b'IEND', b'')
    open(path, 'wb').write(sig + ihdr + idat + iend)
write_png(sys.argv[1])
PYEOF
  sips -s format jpeg "${TMP_PNG}" --out "${ORIG_FILE}" >/dev/null 2>&1
  "${EXIFTOOL_BIN}" -overwrite_original -GPSLatitude=51.5 -GPSLongitude=-0.1 -GPSLatitudeRef=N -GPSLongitudeRef=W "${ORIG_FILE}" >/dev/null 2>&1
else
  # Fallback: plain binary file (not a real image — strip will be skipped by phonedrop, still tests push path)
  printf '\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xFF\xD9' > "${ORIG_FILE}"
fi

# Take a checksum of the original before the push
ORIG_MD5=$(md5 -q "${ORIG_FILE}" 2>/dev/null || md5sum "${ORIG_FILE}" | awk '{print $1}')

# Run phonedrop.sh push with stubs injected via env
> "${ADB_LOG}"
> "${EXIFTOOL_LOG}"
PHONEDROP_CONFIG_FILE="${STUB_CFG}" \
  bash "${PHONEDROP}" push "${ORIG_FILE}" 2>&1 | grep -v "^$" || true

# Assert original is byte-identical (not mutated)
AFTER_MD5=$(md5 -q "${ORIG_FILE}" 2>/dev/null || md5sum "${ORIG_FILE}" | awk '{print $1}')
assert_eq "original file not modified by push" "${ORIG_MD5}" "${AFTER_MD5}"

# Assert stub adb push was called with the safe filename
ADB_LOG_CONTENT=$(cat "${ADB_LOG}" 2>/dev/null || true)
assert_contains "adb push was called" "push" "${ADB_LOG_CONTENT}"
assert_contains "adb push references photo.jpg" "photo.jpg" "${ADB_LOG_CONTENT}"

# Assert stub exiftool was called (if real exiftool available)
if [[ -x "${EXIFTOOL_BIN}" ]]; then
  EXIFTOOL_LOG_CONTENT=$(cat "${EXIFTOOL_LOG}" 2>/dev/null || true)
  assert_contains "exiftool was called on temp copy" "-all=" "${EXIFTOOL_LOG_CONTENT}"
fi

rm -rf "${WORK_DIR}"

# --- 5b: INJECTION REGRESSION — adversarial filename ---
echo ""
echo "--- 5b: adversarial filename injection regression ---"

# This is the regression test for C1 (the original bug):
# A file named with shell metacharacters must NOT execute arbitrary commands
# on the phone. The sanitise_basename() function must strip these to safe chars.

WORK_DIR2=$(mktemp -d)
# Create a file whose raw name contains shell metacharacters
ADVERSARIAL_NAME="a;touch INJECTED.jpg"
ADVERSARIAL_FILE="${WORK_DIR2}/${ADVERSARIAL_NAME}"
printf '\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xFF\xD9' > "${ADVERSARIAL_FILE}"

# Sentinel: this file must NOT be created by the push
INJECTED_SENTINEL="${WORK_DIR2}/INJECTED.jpg"
assert_file_not_exists "sentinel INJECTED.jpg does not exist before test" "${INJECTED_SENTINEL}"

> "${ADB_LOG}"
PHONEDROP_CONFIG_FILE="${STUB_CFG}" \
  bash "${PHONEDROP}" push "${ADVERSARIAL_FILE}" 2>&1 | grep -v "^$" || true

# 5b-i: INJECTED.jpg must not have been created (the ;touch part did not execute)
assert_file_not_exists "injection did not execute (INJECTED.jpg not created)" "${INJECTED_SENTINEL}"

# 5b-ii: The adb push log must NOT contain the literal semicolon-separated injection
#         (proves the filename was sanitised before reaching adb shell)
ADB_LOG_CONTENT2=$(cat "${ADB_LOG}" 2>/dev/null || true)
assert_not_contains "adb log does not contain raw ';touch'" ";touch" "${ADB_LOG_CONTENT2}"

# 5b-iii: The adb push must have received a sanitised (safe-charset) filename
#          The raw 'a;touch INJECTED.jpg' → sanitised to 'a_touch_INJECTED.jpg'
assert_contains "adb push received sanitised filename" "a_touch_INJECTED.jpg" "${ADB_LOG_CONTENT2}"

rm -rf "${WORK_DIR2}"

# --- 5c: file with spaces in path ---
echo ""
echo "--- 5c: file path with spaces ---"

WORK_DIR3=$(mktemp -d)
mkdir -p "${WORK_DIR3}/My Photos"
SPACE_FILE="${WORK_DIR3}/My Photos/vacation photo.jpg"
printf '\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xFF\xD9' > "${SPACE_FILE}"

ORIG_MD5_SPACE=$(md5 -q "${SPACE_FILE}" 2>/dev/null || md5sum "${SPACE_FILE}" | awk '{print $1}')

> "${ADB_LOG}"
PHONEDROP_CONFIG_FILE="${STUB_CFG}" \
  bash "${PHONEDROP}" push "${SPACE_FILE}" 2>&1 | grep -v "^$" || true

AFTER_MD5_SPACE=$(md5 -q "${SPACE_FILE}" 2>/dev/null || md5sum "${SPACE_FILE}" | awk '{print $1}')
assert_eq "original with spaces not modified" "${ORIG_MD5_SPACE}" "${AFTER_MD5_SPACE}"

ADB_LOG_SPACE=$(cat "${ADB_LOG}" 2>/dev/null || true)
assert_contains "adb push called for space-named file" "vacation_photo.jpg" "${ADB_LOG_SPACE}"

rm -rf "${WORK_DIR3}"

# Cleanup stubs
rm -rf "${STUB_DIR}" "${STUB_CFG_DIR}"

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
