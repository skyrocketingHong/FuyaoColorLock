#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="$ROOT/build/override-plan-tests"
mkdir -p "$ROOT/build"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos13.0 \
  "$ROOT/Sources/FuyaoColorLock/EDIDPatch.swift" \
  "$ROOT/Sources/FuyaoColorLock/EDIDOverridePlan.swift" \
  "$ROOT/Tests/EDIDOverridePlanTests.swift" -o "$OUTPUT"
"$OUTPUT"
