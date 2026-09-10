#!/usr/bin/env bash
#
# Build Float (Release) and package it into an ad-hoc signed .dmg.
#
# Ad-hoc is enough to run on your own machines. It is NOT notarized, so the
# first launch on every other Mac needs: right-click Float.app -> Open once
# (or: xattr -dr com.apple.quarantine /Applications/Float.app).
#
# For a clean double-click install everywhere, switch to Developer ID +
# notarization later.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
SCHEME="Float"
VERSION="$(sed -n 's/.*MARKETING_VERSION: *"\(.*\)".*/\1/p' project.yml | head -1)"
VERSION="${VERSION:-dev}"
DMG="$DIST_DIR/Float-$VERSION.dmg"

command -v xcodegen >/dev/null || { echo "xcodegen not found (brew install xcodegen)"; exit 1; }

echo ">> Regenerating project"
xcodegen generate >/dev/null

echo ">> Building $SCHEME (Release)"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project Float.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build | tail -1

APP="$BUILD_DIR/Build/Products/Release/Float.app"
[ -d "$APP" ] || { echo "build failed: $APP missing"; exit 1; }

echo ">> Ad-hoc signing"
ENT="$ROOT/Resources/Float.entitlements"
if [ -f "$ENT" ]; then
  codesign --force --deep --sign - --timestamp=none --entitlements "$ENT" "$APP"
else
  codesign --force --deep --sign - --timestamp=none "$APP"
fi
codesign --verify --verbose "$APP"

echo ">> Building $DMG"
mkdir -p "$DIST_DIR"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Float.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "Float $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null
rm -rf "$STAGE"

echo
echo "Done: $DMG"
echo
echo "Install on another Mac:"
echo "  1. open the .dmg, drag Float into Applications"
echo "  2. right-click Float.app -> Open  (once, to clear Gatekeeper)"
