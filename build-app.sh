#!/bin/bash
# Build PhoneHub.app — native SwiftUI device mirroring dashboard.
# Signs with a stable self-signed identity so Accessibility grants survive
# rebuilds. Ad-hoc signing changes the code hash and forces re-granting AX.
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/cache/clang}"

APP="PhoneHub.app"
BIN="PhoneHub"
CONTENTS="${APP}/Contents"
IDENTITY="PhoneHub Self-Signed"
SIGN_KC="${HOME}/Library/Keychains/phonehub-signing.keychain-db"
KC_PASS="phonehubpass"

ensure_identity() {
  if security find-identity -p codesigning "${SIGN_KC}" 2>/dev/null | grep -q "${IDENTITY}"; then
    return 0
  fi

  echo "→ Creating stable signing identity '${IDENTITY}' (one-time) ..."
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN

  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "${tmp}/key.pem" -out "${tmp}/cert.pem" \
    -subj "/CN=${IDENTITY}" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=digitalSignature" >/dev/null 2>&1

  openssl pkcs12 -export -inkey "${tmp}/key.pem" -in "${tmp}/cert.pem" \
    -out "${tmp}/identity.p12" -passout "pass:${KC_PASS}" \
    -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

  if [[ ! -f "${SIGN_KC}" ]]; then
    security create-keychain -p "${KC_PASS}" "${SIGN_KC}"
  fi
  security unlock-keychain -p "${KC_PASS}" "${SIGN_KC}"
  security set-keychain-settings "${SIGN_KC}"
  security import "${tmp}/identity.p12" -k "${SIGN_KC}" -P "${KC_PASS}" \
    -T /usr/bin/codesign -A >/dev/null 2>&1
  security set-key-partition-list -S apple-tool:,apple:,unsigned: -s -k "${KC_PASS}" "${SIGN_KC}" >/dev/null 2>&1 || true

  local current=()
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"
    [[ -n "$line" ]] && current+=("$line")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s ${current[@]+"${current[@]}"} "${SIGN_KC}" >/dev/null 2>&1 || true
  echo "  ✓ identity created in ${SIGN_KC}"
}

echo "→ Compiling (release) ..."
swift build -c release --disable-sandbox --manifest-cache local

echo "→ Assembling ${APP} ..."
rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp ".build/release/${BIN}" "${CONTENTS}/MacOS/${BIN}"
cp Info.plist "${CONTENTS}/Info.plist"

ensure_identity

security find-identity -p codesigning "${SIGN_KC}" | grep -q "${IDENTITY}"
security unlock-keychain -p "${KC_PASS}" "${SIGN_KC}" >/dev/null 2>&1 || true
codesign --force --deep --sign "${IDENTITY}" --keychain "${SIGN_KC}" "${APP}"
echo "  signed with stable identity — Accessibility grant will persist across rebuilds"

echo "✓ Built ${APP}"
echo "  Run: open ${APP}   (or install: cp -r ${APP} /Applications/)"
