#!/bin/zsh
# Builds the FuyaoColorLock menu-bar app into build/FuyaoColorLock.app.
# Tool locations resolve through xcrun so the script survives Xcode updates.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/FuyaoColorLock.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

SWIFTC="$(xcrun --find swiftc)"
PLUTIL="$(xcrun --find plutil)"
CODESIGN="$(xcrun --find codesign)"
SDK="$(xcrun --show-sdk-path)"

"$SWIFTC" -O \
  -sdk "$SDK" \
  -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework CoreGraphics -framework ServiceManagement \
  "$ROOT"/Sources/FuyaoColorLock/*.swift \
  -o "$CONTENTS/MacOS/FuyaoColorLock"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
"$PLUTIL" -lint "$CONTENTS/Info.plist" >/dev/null

"$CODESIGN" --force --sign - "$APP" >/dev/null 2>&1

echo "Built $APP"
"$PLUTIL" -extract CFBundleShortVersionString raw "$CONTENTS/Info.plist" | xargs -I{} echo "Version {}"
