#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/edid-tests"
mkdir -p "$ROOT/build"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos13.0 \
  "$ROOT/Sources/FuyaoColorLock/EDIDPatch.swift" \
  "$ROOT/Tests/EDIDPatchTests.swift" -o "$OUTPUT"
"$OUTPUT" "$@"
