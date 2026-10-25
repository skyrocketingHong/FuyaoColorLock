#!/bin/zsh
# Builds the FuyaoColorLock menu-bar app into build/FuyaoColorLock.app.
# Tool locations resolve through xcrun so the script survives Xcode updates.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/FuyaoColorLock.app"
mkdir -p "$ROOT/build"
STAGING="$(mktemp -d "$ROOT/build/.app-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="$STAGING/FuyaoColorLock.app"
CONTENTS="$STAGED_APP/Contents"
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
for localization in "$ROOT"/Resources/*.lproj(N); do
  cp -R "$localization" "$CONTENTS/Resources/"
done

"$CODESIGN" --force --sign - "$STAGED_APP"
"$CODESIGN" --verify --deep --strict "$STAGED_APP"

rm -rf "$APP"
mv "$STAGED_APP" "$APP"
CONTENTS="$APP/Contents"

echo "Built $APP"
"$PLUTIL" -extract CFBundleShortVersionString raw "$CONTENTS/Info.plist" | xargs -I{} echo "Version {}"
