#!/bin/bash
# Crea il DMG di CalenTask sul tuo Mac (stessa ricetta del workflow DMG),
# utile quando i minuti di GitHub Actions sono esauriti.
#
# Uso:   scripts/build-dmg.sh 0.1.0        → build/CalenTask-v0.1.0.dmg
# Poi (facoltativo, con GitHub CLI):
#   gh release create v0.1.0 build/CalenTask-v0.1.0.dmg --draft --title "CalenTask v0.1.0"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Indica la versione, es. scripts/build-dmg.sh 0.1.0}"
BUILD_NUMBER="${2:-$(git rev-list --count HEAD)}"
NAME="CalenTask-v$VERSION"

xcodebuild build \
  -project CalenTask.xcodeproj \
  -scheme CalenTask \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  | grep -E "error:|\*\* BUILD" || true

APP="build/Build/Products/Release/CalenTask.app"
test -d "$APP" || { echo "Build fallita: $APP non esiste"; exit 1; }
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

rm -rf build/dmg && mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "CalenTask" -srcfolder build/dmg -ov -format UDZO "build/$NAME.dmg"
echo "✅ build/$NAME.dmg (versione $VERSION, build $BUILD_NUMBER)"
