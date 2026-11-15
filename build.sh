#!/bin/bash
# Builds build/Sidekick.app. Needs Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Sidekick.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Sidekick" "$APP/Contents/MacOS/Sidekick"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with your Apple Development certificate if you have one: its identity stays the same
# across rebuilds, so macOS keeps Sidekick's permissions. Otherwise sign ad-hoc (re-grant after each build).
ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${ID:--}" "$APP"
echo "Signed with: ${ID:-ad-hoc}"

echo "Built $APP"
echo "Install: cp -R $APP /Applications/ && open /Applications/Sidekick.app"
