#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/native-mode-tests"
mkdir -p "$ROOT/build"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos13.0 \
  -framework CoreGraphics -framework IOKit \
  "$ROOT/Sources/FuyaoColorLock/CoreDisplayModes.swift" \
  "$ROOT/Sources/FuyaoColorLock/DisplayCatalog.swift" \
  "$ROOT/Tests/NativeConnectionModeTests.swift" -o "$OUTPUT"
"$OUTPUT"
