#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: scripts/release.sh <version> (for example: v1.2.0)" >&2
}

if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must match vMAJOR.MINOR.PATCH." >&2
  usage
  exit 1
fi

cd "$(dirname "$0")/.."

version="$1"
archive="PhoneHub-${version}-macos.zip"

./build-app.sh

rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent PhoneHub.app "$archive"

echo "SHA-256 checksum:"
shasum -a 256 "$archive"

echo
echo "Release asset: $archive"
echo "Publish the SHA-256 checksum above with the release."
echo "Run this command to create the GitHub release:"
echo "gh release create $version \"$archive\" --title \"PhoneHub $version\" --generate-notes"
echo "Note: PhoneHub is self-signed; users must right-click → Open on first launch to pass Gatekeeper."
