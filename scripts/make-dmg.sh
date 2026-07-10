#!/bin/bash
# Builds a Release version of Shine, signs it ad-hoc (no paid Apple
# Developer membership required), and packages it as a .dmg for GitHub
# Releases. Output: build/Shine-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Shine"
BUILD_DIR="build"

xcodebuild -project "$APP_NAME.xcodeproj" \
           -scheme "$APP_NAME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGN_STYLE=Manual \
           CODE_SIGNING_REQUIRED=YES \
           DEVELOPMENT_TEAM="" \
           build

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

# Re-sign ad-hoc, keeping the hardened runtime flag.
codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --verbose=2 "$APP"

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo
echo "Created $DMG"
