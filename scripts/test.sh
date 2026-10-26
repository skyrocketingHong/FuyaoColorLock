#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
"$ROOT/scripts/test-models.sh"
"$ROOT/scripts/test-native-modes.sh"
"$ROOT/scripts/test-display-selection.sh"
"$ROOT/scripts/test-mode-locks.sh"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos13.0 \
  "$ROOT/Sources/FuyaoColorLock/PanelLayout.swift" \
  "$ROOT/Tests/PanelLayoutTests.swift" -o "$ROOT/build/panel-layout-tests"
"$ROOT/build/panel-layout-tests"
"$ROOT/scripts/test-edid-swift.sh"
"$ROOT/scripts/test-override-plan.sh"
python3 -B "$ROOT/Tests/test_patch_edid.py"
