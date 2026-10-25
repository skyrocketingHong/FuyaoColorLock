#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/model-tests"
mkdir -p "$ROOT/build"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos13.0 \
  -framework AppKit -framework CoreGraphics -framework IOKit \
  "$ROOT/Sources/FuyaoColorLock/DisplayCatalog.swift" \
  "$ROOT/Sources/FuyaoColorLock/CoreDisplayModes.swift" \
  "$ROOT/Sources/FuyaoColorLock/Settings.swift" \
  "$ROOT/Sources/FuyaoColorLock/ModeLock.swift" \
  "$ROOT/Tests/DisplayModelTests.swift" -o "$OUTPUT"
"$OUTPUT"
