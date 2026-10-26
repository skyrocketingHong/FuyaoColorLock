#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos13.0 \
  "$ROOT/Sources/FuyaoColorLock/DisplaySelection.swift" \
  "$ROOT/Tests/DisplaySelectionTests.swift" -o "$ROOT/build/display-selection-tests"
"$ROOT/build/display-selection-tests"
