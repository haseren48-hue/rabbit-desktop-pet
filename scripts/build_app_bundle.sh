#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/RabbitDesktopPet.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources/RabbitDesktopPet_RabbitDesktopPet.bundle"
BUILD_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/debug"

cd "$PROJECT_DIR"
swift build

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/RabbitDesktopPet" "$MACOS_DIR/RabbitDesktopPet"
ditto "$PROJECT_DIR/Sources/RabbitDesktopPet/Resources" "$RESOURCES_DIR"

plutil -create xml1 "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleName -string RabbitDesktopPet "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleDisplayName -string RabbitDesktopPet "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIdentifier -string com.local.RabbitDesktopPet "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleExecutable -string RabbitDesktopPet "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleVersion -string 1 "$CONTENTS_DIR/Info.plist"
plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
plutil -insert NSAccessibilityUsageDescription -string 'LINE、Outlook、Codexの通知をウサギの吹き出しに表示します。' "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - --identifier com.local.RabbitDesktopPet "$APP_DIR"
echo "$APP_DIR"
