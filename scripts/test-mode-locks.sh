#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos13.0 \
  -framework AppKit -framework CoreGraphics -framework IOKit \
  "$ROOT/Sources/FuyaoColorLock/DisplayCatalog.swift" \
  "$ROOT/Sources/FuyaoColorLock/CoreDisplayModes.swift" \
  "$ROOT/Sources/FuyaoColorLock/PrivateSLS.swift" \
  "$ROOT/Sources/FuyaoColorLock/Settings.swift" \
  "$ROOT/Sources/FuyaoColorLock/ModeLock.swift" \
  "$ROOT/Sources/FuyaoColorLock/DisplayBackend.swift" \
  "$ROOT/Sources/FuyaoColorLock/DisplayGuard.swift" \
  "$ROOT/Tests/ModeLockTests.swift" -o "$ROOT/build/mode-lock-tests"
"$ROOT/build/mode-lock-tests"
