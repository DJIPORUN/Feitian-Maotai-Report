#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/飞天茅台实时报表.app"
MACOS="$APP/Contents/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"

xcrun swiftc \
  -parse-as-library \
  -swift-version 5 \
  -framework SwiftUI \
  -framework Charts \
  -framework AppKit \
  -o "$MACOS/FeitianReport" \
  "$ROOT/Sources/FeitianReport/ComparisonLogic.swift" \
  "$ROOT/Sources/FeitianReport/App.swift"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>FeitianReport</string>
  <key>CFBundleIdentifier</key><string>com.local.feitian.maotai.report</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>飞天茅台实时报表</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS/FeitianReport"
echo "$APP"
