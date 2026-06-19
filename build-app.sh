#!/bin/bash
# Build PhoneHub.app — native SwiftUI device-control dashboard.
set -euo pipefail
cd "$(dirname "$0")"

# Use Command Line Tools toolchain to avoid the Xcode license gate (matches sibling apps).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

echo "→ Compiling (release) ..."
swift build -c release

APP="PhoneHub.app"
BIN="PhoneHub"
CONTENTS="${APP}/Contents"

echo "→ Assembling ${APP} ..."
rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp ".build/release/${BIN}" "${CONTENTS}/MacOS/${BIN}"
cp Info.plist "${CONTENTS}/Info.plist"

echo "→ Ad-hoc signing ..."
codesign --force --deep --sign - "${APP}"

echo "✓ Built ${APP}"
echo "  Run: open ${APP}   (or install: cp -r ${APP} /Applications/)"
