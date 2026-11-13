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
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Install: cp -R $APP /Applications/ && open /Applications/Sidekick.app"
