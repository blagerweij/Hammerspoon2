#!/usr/bin/env bash
#
# Builds "Hammerspoon 2 Test App.app", the app the integration tests launch instead of Finder or
# Chess (see TestApp.swift next to this script), and prints its path. Does nothing when it is up to date.
#
# An app bundle is only a folder with an executable and an Info.plist, so `swiftc` and a few
# lines here are enough; there is no Xcode target for it. The tests run this script themselves
# (TestAppControl.swift).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../../.."

SOURCE="$HERE/TestApp.swift"
APP_BUNDLE="build/testapp/Hammerspoon 2 Test App.app"
CONTENTS="$APP_BUNDLE/Contents"
EXECUTABLE="$CONTENTS/MacOS/Hammerspoon2TestApp"

if [[ ! -x "$EXECUTABLE" || "$SOURCE" -nt "$EXECUTABLE" || "$0" -nt "$EXECUTABLE" ]]; then
    rm -rf "$APP_BUNDLE"
    mkdir -p "$CONTENTS/MacOS"

    # Xcode's build settings in the environment (SDKROOT and friends) would mislead swiftc
    env -i PATH="/usr/bin:/bin" HOME="$HOME" xcrun swiftc -O -parse-as-library -D TEST_APP "$SOURCE" -o "$EXECUTABLE" >&2

    cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Hammerspoon2TestApp</string>
  <key>CFBundleIdentifier</key>
  <string>net.tenshu.Hammerspoon-2.TestApp</string>
  <key>CFBundleName</key>
  <string>Hammerspoon 2 Test App</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
fi

echo "$PWD/$APP_BUNDLE"
