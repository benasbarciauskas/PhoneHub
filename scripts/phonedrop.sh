#!/usr/bin/env bash
# phonedrop.sh — PhoneDrop core logic
# Verbs: push <files...> | connect | status | install | config | check
#
# All tool paths are resolved at install time and stored in config.
# NEVER run with direct shell interpolation of user-supplied paths.
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CONFIG_DIR="${PHONEDROP_CONFIG_DIR:-${HOME}/.config/phonedrop}"
CONFIG_FILE="${PHONEDROP_CONFIG_FILE:-${CONFIG_DIR}/config}"
SUPPORT_DIR="${HOME}/Library/Application Support/PhoneDrop"
APP_DEST="${HOME}/Applications/PhoneDrop.app"

# Source the config if it exists
load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
  fi
}

# Defaults (may be overridden by config)
PHONE_HOST="${PHONE_HOST:-}"
ADB_PORT="${ADB_PORT:-5555}"
DEST="${DEST:-/sdcard/DCIM/PhoneDrop/}"

# Absolute tool paths (written at install; fall back to known locations)
ADB_BIN="${ADB_BIN:-/opt/homebrew/bin/adb}"
EXIFTOOL_BIN="${EXIFTOOL_BIN:-/opt/homebrew/bin/exiftool}"
TAILSCALE_BIN="${TAILSCALE_BIN:-/usr/local/bin/tailscale}"

# ---------------------------------------------------------------------------
# Input sanitisation
# ---------------------------------------------------------------------------

# Validate DEST contains only safe path characters (no shell metacharacters).
# Called after load_config / source config.
validate_dest() {
  # Allow: / A-Z a-z 0-9 . _ -   Reject everything else.
  if [[ ! "${DEST}" =~ ^[A-Za-z0-9./_-]+$ ]]; then
    echo "phonedrop: error: DEST config value contains unsafe characters: ${DEST}" >&2
    exit 1
  fi
}

# Sanitise a filename to a strict safe allowlist: [A-Za-z0-9._-]
# Replaces unsafe chars with '_', strips leading '-', rejects empty/./ ..
sanitise_basename() {
  local name="$1"
  # Replace any char NOT in [A-Za-z0-9._-] with underscore
  local safe
  safe=$(printf '%s' "${name}" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')
  # Strip any leading dashes (prevent option injection into adb)
  safe="${safe#-}"
  safe="${safe##*( )}"
  # Reject empty, dot, or dotdot
  if [[ -z "${safe}" || "${safe}" == "." || "${safe}" == ".." ]]; then
    echo "phonedrop: error: sanitised filename is empty or reserved: '${name}'" >&2
    return 1
  fi
  printf '%s' "${safe}"
}

# Shell-quote a string for safe embedding inside a single-quoted remote shell arg.
# Turns:  foo'bar  →  foo'\''bar  (POSIX single-quote escaping)
sq_escape() {
  local s="$1"
  printf '%s' "${s}" | sed "s/'/'\\\\''/g"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Safe macOS notification — values passed via osascript argv, not string interpolation.
notify() {
  local title="${1:-PhoneDrop}"
  local msg="${2:-Done}"
  osascript << OSASCRIPT 2>/dev/null || true
on run
  display notification "${msg}" with title "${title}"
end run
OSASCRIPT
}

die() {
  local msg="$*"
  echo "phonedrop: error: ${msg}" >&2
  notify "PhoneDrop Error" "${msg}"
  exit 1
}

require_config() {
  load_config
  [[ -f "${CONFIG_FILE}" ]] || die "Config not found. Run: phonedrop.sh install"
  [[ -n "${PHONE_HOST}" ]] || die "PHONE_HOST not set in ${CONFIG_FILE}. Edit it and set PHONE_HOST."
}

require_tool() {
  local bin="$1"
  local name="$2"
  [[ -x "${bin}" ]] || die "${name} not found at ${bin}. Run: phonedrop.sh install"
}

# ---------------------------------------------------------------------------
# Verb: connect
# ---------------------------------------------------------------------------
cmd_connect() {
  load_config
  [[ -n "${PHONE_HOST}" ]] || die "PHONE_HOST not set in config. Edit ${CONFIG_FILE}."
  require_tool "${ADB_BIN}" "adb"

  echo "phonedrop: connecting to ${PHONE_HOST}:${ADB_PORT} ..."
  local result
  result=$("${ADB_BIN}" connect "${PHONE_HOST}:${ADB_PORT}" 2>&1) || true
  if echo "${result}" | grep -qiE "connected|already connected"; then
    echo "phonedrop: ${result}"
    return 0
  else
    die "Could not connect to ${PHONE_HOST}:${ADB_PORT}. Re-pair Wireless Debugging on the phone and try again. (adb said: ${result})"
  fi
}

# ---------------------------------------------------------------------------
# Verb: status
# ---------------------------------------------------------------------------
cmd_status() {
  load_config
  echo "=== PhoneDrop status ==="
  echo "Config:       ${CONFIG_FILE}"
  echo "PHONE_HOST:   ${PHONE_HOST:-<not set>}"
  echo "ADB_PORT:     ${ADB_PORT}"
  echo "DEST:         ${DEST}"
  echo "ADB_BIN:      ${ADB_BIN} $([ -x "${ADB_BIN}" ] && echo "(ok)" || echo "(NOT FOUND)")"
  echo "EXIFTOOL_BIN: ${EXIFTOOL_BIN} $([ -x "${EXIFTOOL_BIN}" ] && echo "(ok)" || echo "(NOT FOUND)")"
  echo "TAILSCALE_BIN:${TAILSCALE_BIN} $([ -x "${TAILSCALE_BIN}" ] && echo "(ok)" || echo "(NOT FOUND)")"
  echo ""
  if [[ -x "${ADB_BIN}" ]]; then
    echo "=== adb devices ==="
    "${ADB_BIN}" devices 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# Verb: config
# ---------------------------------------------------------------------------
cmd_config() {
  echo "Config path: ${CONFIG_FILE}"
  if [[ -f "${CONFIG_FILE}" ]]; then
    cat "${CONFIG_FILE}"
  else
    echo "(config file does not exist yet — run: phonedrop.sh install)"
  fi
}

# ---------------------------------------------------------------------------
# Verb: install
# ---------------------------------------------------------------------------
cmd_install() {
  # Resolve absolute tool paths
  local adb_bin exiftool_bin tailscale_bin
  adb_bin=$(command -v adb 2>/dev/null || echo "/opt/homebrew/bin/adb")
  exiftool_bin=$(command -v exiftool 2>/dev/null || echo "/opt/homebrew/bin/exiftool")
  tailscale_bin=$(command -v tailscale 2>/dev/null || echo "/usr/local/bin/tailscale")

  # Prefer known homebrew paths if the PATH-resolved binary isn't executable
  [[ -x "${adb_bin}" ]]       || adb_bin="/opt/homebrew/bin/adb"
  [[ -x "${exiftool_bin}" ]]  || exiftool_bin="/opt/homebrew/bin/exiftool"
  [[ -x "${tailscale_bin}" ]] || tailscale_bin="/usr/local/bin/tailscale"

  # Create config dir
  mkdir -p "${CONFIG_DIR}"

  # Seed config if it doesn't exist
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    local phone_host=""
    if [[ -t 0 ]]; then
      read -r -p "Enter phone Tailscale MagicDNS hostname (e.g. motorola): " phone_host
    fi
    cat > "${CONFIG_FILE}" << EOF
# PhoneDrop configuration
# Edit PHONE_HOST to match your phone's Tailscale MagicDNS name.

PHONE_HOST="${phone_host:-YOUR_PHONE_HOSTNAME}"
ADB_PORT="5555"
DEST="/sdcard/DCIM/PhoneDrop/"

# Absolute tool paths (resolved at install time)
ADB_BIN="${adb_bin}"
EXIFTOOL_BIN="${exiftool_bin}"
TAILSCALE_BIN="${tailscale_bin}"
EOF
    echo "phonedrop: config written to ${CONFIG_FILE}"
    if [[ -z "${phone_host}" ]]; then
      echo "phonedrop: Set PHONE_HOST in ${CONFIG_FILE} before using PhoneDrop."
    fi
  else
    echo "phonedrop: config already exists at ${CONFIG_FILE} (not overwritten)"
    # Update only tool paths in existing config
    sed -i '' \
      -e "s|^ADB_BIN=.*|ADB_BIN=\"${adb_bin}\"|" \
      -e "s|^EXIFTOOL_BIN=.*|EXIFTOOL_BIN=\"${exiftool_bin}\"|" \
      -e "s|^TAILSCALE_BIN=.*|TAILSCALE_BIN=\"${tailscale_bin}\"|" \
      "${CONFIG_FILE}"
    echo "phonedrop: updated tool paths in existing config"
  fi

  # Install logic script to Application Support
  mkdir -p "${SUPPORT_DIR}"
  local self
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  cp "${self}" "${SUPPORT_DIR}/phonedrop.sh"
  chmod +x "${SUPPORT_DIR}/phonedrop.sh"
  echo "phonedrop: logic script installed to ${SUPPORT_DIR}/phonedrop.sh"

  # Locate the droplet source (same dir as this script)
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local droplet_src="${script_dir}/phonedrop-droplet.applescript"
  if [[ ! -f "${droplet_src}" ]]; then
    die "Droplet source not found at ${droplet_src}. Clone the repo first."
  fi

  # Compile the AppleScript droplet
  mkdir -p "${HOME}/Applications"
  osacompile -o "${APP_DEST}" "${droplet_src}"
  echo "phonedrop: droplet compiled → ${APP_DEST}"
  echo ""
  echo "Done! Drag ${APP_DEST} to your Dock, then drop photos onto it."
}

# ---------------------------------------------------------------------------
# Verb: check (smoke test)
# ---------------------------------------------------------------------------
cmd_check() {
  load_config
  local errors=0

  echo "=== PhoneDrop smoke test ==="

  # 1. Config present
  if [[ -f "${CONFIG_FILE}" ]]; then
    echo "[ok] config: ${CONFIG_FILE}"
  else
    echo "[FAIL] config not found: ${CONFIG_FILE}"
    errors=$((errors+1))
  fi

  # 2. Tool paths resolve
  for pair in "${ADB_BIN}:adb" "${EXIFTOOL_BIN}:exiftool" "${TAILSCALE_BIN}:tailscale"; do
    local bin="${pair%%:*}"
    local name="${pair##*:}"
    if [[ -x "${bin}" ]]; then
      echo "[ok] ${name}: ${bin}"
    else
      echo "[FAIL] ${name} not executable: ${bin}"
      errors=$((errors+1))
    fi
  done

  # 3. EXIF strip assertion — create 1px JPEG, inject GPS, strip, verify gone
  echo "--- EXIF strip test ---"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' EXIT
  local orig="${tmp_dir}/orig.jpg"
  local stripped="${tmp_dir}/stripped.jpg"

  # Create minimal 1x1 JPEG via sips (macOS built-in)
  if command -v sips >/dev/null 2>&1; then
    local tmp_png="${tmp_dir}/pixel.png"
    python3 - "${tmp_png}" << 'PYEOF'
import sys, struct, zlib
def write_png(path):
    raw = b'\x00\x00'  # filter byte + 1-byte gray pixel
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
    sips -s format jpeg "${tmp_png}" --out "${orig}" >/dev/null 2>&1 || true
  fi

  if [[ ! -f "${orig}" ]]; then
    echo "[SKIP] could not create test JPEG (sips unavailable)"
  elif [[ ! -x "${EXIFTOOL_BIN}" ]]; then
    echo "[SKIP] exiftool not found — cannot run strip assertion"
    errors=$((errors+1))
  else
    "${EXIFTOOL_BIN}" -overwrite_original \
      -GPSLatitude=51.5 -GPSLongitude=-0.1 \
      -GPSLatitudeRef=N -GPSLongitudeRef=W \
      "${orig}" >/dev/null 2>&1

    local gps_before
    gps_before=$("${EXIFTOOL_BIN}" -GPSLatitude "${orig}" 2>/dev/null || true)
    [[ -z "${gps_before}" ]] && echo "[WARN] GPS injection may have failed"

    cp "${orig}" "${stripped}"
    "${EXIFTOOL_BIN}" -overwrite_original -all= "${stripped}" >/dev/null 2>&1

    local gps_after
    gps_after=$("${EXIFTOOL_BIN}" -GPS:all "${stripped}" 2>/dev/null || true)
    if [[ -z "${gps_after}" ]]; then
      echo "[ok] EXIF/GPS strip: no GPS tags after strip"
    else
      echo "[FAIL] EXIF/GPS strip: GPS tags still present:"
      echo "  ${gps_after}"
      errors=$((errors+1))
    fi
  fi
  # tmp_dir cleaned by EXIT trap

  # 4. adb connect (only if PHONE_HOST is configured)
  if [[ -n "${PHONE_HOST}" ]] && [[ "${PHONE_HOST}" != "YOUR_PHONE_HOSTNAME" ]]; then
    echo "--- adb connect test ---"
    if [[ -x "${ADB_BIN}" ]]; then
      local result
      result=$("${ADB_BIN}" connect "${PHONE_HOST}:${ADB_PORT}" 2>&1) || true
      if echo "${result}" | grep -qiE "connected|already connected"; then
        echo "[ok] adb connect: ${result}"
        # Verify DEST parent writable via safely-quoted remote command
        local dest_safe
        dest_safe="$(sq_escape "${DEST}")"
        local writable
        writable=$("${ADB_BIN}" shell "test -w '${dest_safe}' && echo yes || echo no" 2>/dev/null || echo "unknown")
        echo "[info] DEST writable: ${writable}"
      else
        echo "[FAIL] adb connect failed: ${result}"
        errors=$((errors+1))
      fi
    fi
  else
    echo "[skip] adb connect: PHONE_HOST not configured"
  fi

  echo ""
  if [[ "${errors}" -eq 0 ]]; then
    echo "=== All checks passed ==="
    return 0
  else
    echo "=== ${errors} check(s) failed ==="
    notify "PhoneDrop" "smoke test: ${errors} check(s) failed — see terminal"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Verb: push <files...>
# ---------------------------------------------------------------------------
cmd_push() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: phonedrop.sh push <file> [file ...]" >&2
    exit 1
  fi

  require_config
  validate_dest
  require_tool "${ADB_BIN}" "adb"
  require_tool "${EXIFTOOL_BIN}" "exiftool"

  # Ensure adb connected (idempotent)
  local conn_result
  conn_result=$("${ADB_BIN}" connect "${PHONE_HOST}:${ADB_PORT}" 2>&1) || true
  if ! echo "${conn_result}" | grep -qiE "connected|already connected"; then
    die "Cannot connect to phone (${PHONE_HOST}:${ADB_PORT}). Re-pair Wireless Debugging on the phone."
  fi

  # Ensure destination dir exists on phone — DEST is validated above (safe charset)
  local dest_safe
  dest_safe="$(sq_escape "${DEST}")"
  "${ADB_BIN}" shell "mkdir -p '${dest_safe}'" 2>/dev/null || true

  local tmp_dir
  tmp_dir=$(mktemp -d)
  # Always clean up temp dir on exit, even on die/abort mid-loop
  trap '[[ -n "${tmp_dir:-}" ]] && rm -rf "${tmp_dir}"' EXIT

  local pushed=0
  local failed=0
  local last_error=""

  # Image extensions we strip EXIF from
  local image_exts="jpg jpeg png tif tiff heic heif webp bmp gif"

  # Track index for dedup — two files with the same basename get a suffix
  # (bash 3.2 compatible: use a per-name counter file in a temp subdir)
  local seen_dir
  seen_dir=$(mktemp -d)

  for src in "$@"; do
    if [[ ! -f "${src}" ]]; then
      echo "phonedrop: skipping (not a file): ${src}" >&2
      failed=$((failed+1))
      last_error="not a file: ${src}"
      continue
    fi

    # Sanitise the filename for safe use in remote shell strings
    local raw_basename safe_basename
    raw_basename=$(basename "${src}")
    if ! safe_basename=$(sanitise_basename "${raw_basename}"); then
      echo "phonedrop: skipping (unsafe filename): ${raw_basename}" >&2
      failed=$((failed+1))
      last_error="unsafe filename: ${raw_basename}"
      continue
    fi

    # Dedup: if same safe_basename seen before, insert an index before the extension
    local seen_file="${seen_dir}/${safe_basename}.count"
    if [[ -f "${seen_file}" ]]; then
      local count
      count=$(cat "${seen_file}")
      count=$((count+1))
      printf '%s' "${count}" > "${seen_file}"
      local stem="${safe_basename%.*}"
      local fext="${safe_basename##*.}"
      if [[ "${fext}" == "${safe_basename}" ]]; then
        safe_basename="${safe_basename}_${count}"
      else
        safe_basename="${stem}_${count}.${fext}"
      fi
    else
      printf '0' > "${seen_file}"
    fi

    local tmp_copy="${tmp_dir}/${safe_basename}"

    # Copy to temp (never touch original)
    cp -- "${src}" "${tmp_copy}"

    # Determine if this is an image file (by extension, case-insensitive)
    local ext="${safe_basename##*.}"
    ext=$(printf '%s' "${ext}" | tr '[:upper:]' '[:lower:]')
    local is_image=0
    for imgext in ${image_exts}; do
      if [[ "${ext}" == "${imgext}" ]]; then
        is_image=1
        break
      fi
    done

    # Strip EXIF/GPS if image
    if [[ "${is_image}" -eq 1 ]]; then
      "${EXIFTOOL_BIN}" -overwrite_original -all= "${tmp_copy}" >/dev/null 2>&1 || {
        echo "phonedrop: warning: exiftool strip failed for ${safe_basename}, pushing anyway" >&2
      }
    fi

    # Push to phone using the sanitised basename
    # phone_path is built from validated DEST + sanitised basename — safe to quote
    local phone_path="${DEST}${safe_basename}"
    if "${ADB_BIN}" push "${tmp_copy}" "${phone_path}" >/dev/null 2>&1; then
      # MediaStore scan note: MEDIA_SCANNER_SCAN_FILE is deprecated (no-op) on Android 10+.
      # Files placed in /sdcard/DCIM/ are auto-indexed by MediaStore's DCIM auto-scan.
      # We attempt the broadcast anyway for older Android; failures are silent/ignored.
      # The phone_path here is built from validated DEST + sanitised basename — safe to
      # single-quote in the remote shell string.
      local phone_path_safe
      phone_path_safe="$(sq_escape "${phone_path}")"
      "${ADB_BIN}" shell "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d 'file://${phone_path_safe}'" >/dev/null 2>&1 || true
      pushed=$((pushed+1))
      echo "phonedrop: pushed ${safe_basename} → ${phone_path}"
    else
      failed=$((failed+1))
      last_error="adb push failed for ${safe_basename}"
      echo "phonedrop: error: ${last_error}" >&2
    fi
  done

  # tmp_dir and seen_dir cleaned by EXIT trap (set above)
  rm -rf "${seen_dir}"

  # Notification
  if [[ "${pushed}" -gt 0 ]] && [[ "${failed}" -eq 0 ]]; then
    notify "PhoneDrop" "Sent ${pushed} photo(s) to Motorola"
  elif [[ "${pushed}" -gt 0 ]]; then
    notify "PhoneDrop" "Sent ${pushed} photo(s); ${failed} failed"
  else
    die "All ${failed} file(s) failed. Last error: ${last_error}"
  fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
VERB="${1:-}"
shift || true

case "${VERB}" in
  push)    load_config; cmd_push "$@" ;;
  connect) cmd_connect "$@" ;;
  status)  cmd_status "$@" ;;
  install) cmd_install "$@" ;;
  config)  cmd_config "$@" ;;
  check)   cmd_check "$@" ;;
  *)
    echo "Usage: phonedrop.sh <push|connect|status|install|config|check> [args...]" >&2
    echo ""
    echo "  push <files...>  Strip EXIF/GPS and push files to phone gallery"
    echo "  connect          Connect to phone via adb over Tailscale"
    echo "  status           Show config, tool paths, and adb connection state"
    echo "  install          Install PhoneDrop.app and seed config"
    echo "  config           Print config path and current values"
    echo "  check            Run smoke tests (no phone required for EXIF strip test)"
    exit 1
    ;;
esac
