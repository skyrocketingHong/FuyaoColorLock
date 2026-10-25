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
APP_SDK_VERSION="$(xcrun --show-sdk-version)"
APP_MIN_SYSTEM="$("$PLUTIL" -extract LSMinimumSystemVersion raw "$ROOT/Resources/Info.plist")"

# Keep the deployment floor separate from the SDK used for system UI compatibility.
"$SWIFTC" -O \
  -sdk "$SDK" \
  -target "arm64-apple-macos$APP_MIN_SYSTEM" \
  -Xlinker -platform_version -Xlinker macos -Xlinker "$APP_MIN_SYSTEM" -Xlinker "$APP_SDK_VERSION" \
  -framework AppKit -framework SwiftUI -framework CoreGraphics -framework ServiceManagement \
  "$ROOT"/Sources/FuyaoColorLock/*.swift \
  -o "$CONTENTS/MacOS/FuyaoColorLock"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
"$PLUTIL" -insert DTSDKName -string "macosx$APP_SDK_VERSION" "$CONTENTS/Info.plist"
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
echo "SDK $APP_SDK_VERSION; minimum macOS $APP_MIN_SYSTEM"
"$PLUTIL" -extract CFBundleShortVersionString raw "$CONTENTS/Info.plist" | xargs -I{} echo "Version {}"
